"""Example DAG shipped with the Railway template. It is paused at creation:
unpause it in the UI and trigger it to check that the scheduler and worker run tasks."""
from __future__ import annotations

import datetime

from airflow.sdk import dag, task


@dag(schedule=None, start_date=datetime.datetime(2026, 1, 1), catchup=False, tags=["railway", "example"])
def railway_hello():
    @task
    def hello() -> str:
        import socket
        print(f"Hello from the Airflow worker on {socket.gethostname()}")
        return "hello"

    @task
    def done(value: str) -> None:
        print(f"Upstream task returned {value!r}")

    done(hello())


railway_hello()
