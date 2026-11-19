# Apache Airflow 3.4.0, official image, pinned by version and digest.
# All Airflow services of the Railway template build from this folder;
# each service picks its component with the AIRFLOW_ROLE variable.
FROM apache/airflow:3.4.0@sha256:a8d9d19c563c768b2bc605ef26440f28a9164ea886064e99c599b057432ff572

ENV AIRFLOW__CORE__EXECUTOR=CeleryExecutor \
    AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager \
    AIRFLOW__CORE__LOAD_EXAMPLES=False \
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=True \
    AIRFLOW__CORE__HOSTNAME_CALLABLE=railway_airflow.hostname \
    AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK=True \
    AIRFLOW__CELERY__WORKER_CONCURRENCY=4 \
    FORWARDED_ALLOW_IPS=* \
    CONNECTION_CHECK_MAX_COUNT=0 \
    PYTHONPATH=/opt/railway

COPY --chown=50000:0 dags/ /opt/airflow/dags/
COPY --chmod=755 start.sh /opt/railway/start.sh
COPY health.py railway_airflow.py /opt/railway/

# Start as root only to fix volume ownership; start.sh drops to the airflow user (uid 50000, gid 0).
USER root
ENTRYPOINT ["/opt/railway/start.sh"]
