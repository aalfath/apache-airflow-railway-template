[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/apache-airflow-1?utm_medium=integration&utm_source=button&utm_campaign=apache-airflow)

# Apache Airflow on Railway

A one-click Railway template for [Apache Airflow](https://airflow.apache.org/) **3.4.0**, the full CeleryExecutor stack from Airflow's official Docker Compose setup, with each component as its own Railway service:

| Service | What it runs | Volume |
|---|---|---|
| **Airflow** (public) | `airflow api-server`: web UI, REST API and the Execution API that workers call. Runs `airflow db migrate` and creates the admin user before it starts | none |
| **Airflow Scheduler** | `airflow scheduler`: schedules DAG runs and queues tasks | none |
| **Airflow DAG Processor** | `airflow dag-processor`: parses DAG files into the database | none |
| **Airflow Triggerer** | `airflow triggerer`: runs deferred tasks | `/opt/airflow/logs` |
| **Airflow Worker** | `airflow celery worker`: runs tasks and serves their logs | `/opt/airflow/logs` |
| **Postgres** | Railway Postgres: Airflow's metadata database and Celery result backend | `/var/lib/postgresql/data` |
| **Redis** | Railway Redis: Celery broker | `/data` |

All Airflow services build from the [`airflow/`](airflow/) folder of this repo: a `Dockerfile` that starts `FROM apache/airflow:3.4.0@sha256:a8d9d19c563c768b2bc605ef26440f28a9164ea886064e99c599b057432ff572` (the official image, pinned by version and digest) and a small start script. The `AIRFLOW_ROLE` variable picks the component.

## Variables

Set by the template; nothing to fill in:

- `_AIRFLOW_WWW_USER_USERNAME` / `_AIRFLOW_WWW_USER_PASSWORD` (Airflow service): the admin login. The password is generated; find it in the Airflow service's Variables tab.
- `AIRFLOW_FERNET_SECRET`, `AIRFLOW__API_AUTH__JWT_SECRET`, `AIRFLOW__API__SECRET_KEY`: generated secrets, shared by every Airflow service through reference variables. Don't change them after the first deploy (the Fernet secret encrypts stored connections and variables).
- `DATABASE_URL`, `REDIS_URL`, `AIRFLOW_API_PRIVATE_URL`: references to Postgres, Redis and the API server over the private network.

Optional, on the Airflow service (the other services reference it):

- `DAGS_GIT_URL`: HTTPS URL of a Git repository with your DAGs. When set, every Airflow service loads DAGs from it with Airflow's Git DAG bundle instead of the example folder.
- `DAGS_GIT_BRANCH` (default `main`) and `DAGS_GIT_SUBDIR` (folder inside the repo, default the repo root).

## DAGs

Out of the box the template ships one example DAG, `railway_hello` (paused). Unpause and trigger it to check that the scheduler and the worker run tasks. To run your own DAGs, set `DAGS_GIT_URL` on the Airflow service and redeploy all Airflow services. Airflow pulls the repository again every 60 seconds.

## Updates

Railway notifies everyone who deployed this template when a change is merged to `main` here, for example a new Airflow version. Read [CHANGELOG.md](CHANGELOG.md) before you apply an update: a new Airflow version runs `airflow db migrate` on the first start of the Airflow service. Back up Postgres before a major version upgrade.

## Local test

`local-test/compose.yaml` runs the same services with Docker Compose (test-only passwords): `cd local-test && docker compose up -d --build`, then open http://localhost:8080 and sign in as `admin` / `admin-local-test-pass`.
