#!/usr/bin/env bash
# Start one Airflow component on Railway. AIRFLOW_ROLE picks it:
#   api-server (default; also runs DB migrations and creates the admin user),
#   scheduler, dag-processor, triggerer, worker.
set -euo pipefail
umask 0002

ROLE="${AIRFLOW_ROLE:-api-server}"
AIRFLOW_UID="${AIRFLOW_UID:-50000}"
export PORT="${PORT:-8080}"

log() { echo "[railway] $*"; }

# Volumes mount owned by root: give them to the airflow user, then drop privileges.
if [ "$(id -u)" = "0" ]; then
  for d in /opt/airflow/logs ${EXTRA_OWNED_DIRS:-}; do
    mkdir -p "$d" && chown -R "${AIRFLOW_UID}:0" "$d" 2>/dev/null || true
    chmod -R g+rwX "$d" 2>/dev/null || true
  done
  exec setpriv --reuid="${AIRFLOW_UID}" --regid=0 --init-groups "$0" "$@"
fi

# --- Shared settings, derived from Railway variables -------------------------
if [ -z "${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN:-}" ]; then
  : "${DATABASE_URL:?DATABASE_URL is not set (reference the Postgres service)}"
  db="${DATABASE_URL#postgres://}"; db="${db#postgresql://}"
  export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg://${db}"
fi
export AIRFLOW__CELERY__RESULT_BACKEND="${AIRFLOW__CELERY__RESULT_BACKEND:-db+${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN}}"
if [ -z "${AIRFLOW__CELERY__BROKER_URL:-}" ]; then
  : "${REDIS_URL:?REDIS_URL is not set (reference the Redis service)}"
  export AIRFLOW__CELERY__BROKER_URL="${REDIS_URL%/}/0"
fi
if [ -z "${AIRFLOW__CORE__FERNET_KEY:-}" ]; then
  : "${AIRFLOW_FERNET_SECRET:?AIRFLOW_FERNET_SECRET is not set}"
  # A valid Fernet key (urlsafe base64 of 32 bytes) derived from the generated secret.
  AIRFLOW__CORE__FERNET_KEY="$(python -c 'import base64,hashlib,os;print(base64.urlsafe_b64encode(hashlib.sha256(os.environ["AIRFLOW_FERNET_SECRET"].encode()).digest()).decode())')"
  export AIRFLOW__CORE__FERNET_KEY
fi
if [ -n "${AIRFLOW_API_PRIVATE_URL:-}" ]; then
  export AIRFLOW__CORE__EXECUTION_API_SERVER_URL="${AIRFLOW__CORE__EXECUTION_API_SERVER_URL:-${AIRFLOW_API_PRIVATE_URL%/}/execution/}"
fi

# DAGs: the folder baked into this image, or a Git repository when DAGS_GIT_URL is set.
if [ -n "${DAGS_GIT_URL:-}" ] && [ -z "${AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST:-}" ]; then
  AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST="$(python -c '
import json, os
kw = {"repo_url": os.environ["DAGS_GIT_URL"],
      "tracking_ref": os.environ.get("DAGS_GIT_BRANCH") or "main",
      "refresh_interval": int(os.environ.get("DAGS_GIT_REFRESH_SECONDS") or 60)}
if os.environ.get("DAGS_GIT_SUBDIR"):
    kw["subdir"] = os.environ["DAGS_GIT_SUBDIR"]
print(json.dumps([{"name": "git-dags", "classpath": "airflow.providers.git.bundles.git.GitDagBundle", "kwargs": kw}]))')"
  export AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST
fi

wait_for_db() {
  log "waiting for Postgres and the Airflow schema..."
  for _ in $(seq 1 180); do
    if airflow db check-migrations -t 5 >/dev/null 2>&1; then log "database is ready"; return 0; fi
    sleep 5
  done
  log "database not ready after 15 minutes"; return 1
}

case "$ROLE" in
  api-server)
    for _ in $(seq 1 60); do airflow db check >/dev/null 2>&1 && break; log "waiting for Postgres..."; sleep 5; done
    log "running airflow db migrate"
    airflow db migrate
    if [ -n "${_AIRFLOW_WWW_USER_PASSWORD:-}" ]; then
      user="${_AIRFLOW_WWW_USER_USERNAME:-admin}"
      if airflow users list -o plain 2>/dev/null | awk '{print $2}' | grep -qx "$user"; then
        log "admin user '$user' already exists"
      else
        log "creating admin user '$user'"
        airflow users create --username "$user" --password "$_AIRFLOW_WWW_USER_PASSWORD" \
          --firstname Airflow --lastname Admin --role Admin \
          --email "${_AIRFLOW_WWW_USER_EMAIL:-admin@example.invalid}"
      fi
    fi
    unset _AIRFLOW_WWW_USER_PASSWORD
    exec /usr/bin/dumb-init -- airflow api-server --host "" --port "$PORT" --proxy-headers
    ;;
  scheduler)
    wait_for_db
    export AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_SERVER_PORT="$PORT"
    exec /usr/bin/dumb-init -- airflow scheduler
    ;;
  dag-processor)
    wait_for_db
    python /opt/railway/health.py dag-processor &
    exec /usr/bin/dumb-init -- airflow dag-processor
    ;;
  triggerer)
    wait_for_db
    python /opt/railway/health.py triggerer &
    exec /usr/bin/dumb-init -- airflow triggerer
    ;;
  worker)
    wait_for_db
    python /opt/railway/health.py worker &
    export DUMB_INIT_SETSID=0
    exec /usr/bin/dumb-init -- airflow celery worker --celery-hostname "celery@$(hostname)"
    ;;
  *)
    exec /usr/bin/dumb-init -- airflow "$@"
    ;;
esac
