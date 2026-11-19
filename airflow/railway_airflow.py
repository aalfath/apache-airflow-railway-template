"""Helpers for running Airflow on Railway."""
import os
import socket


def hostname() -> str:
    """Hostname other services can reach over Railway's private network.

    Airflow stores it with each task and job, and the API server uses it to fetch
    task logs from the worker's log server, so it must resolve from other services.
    """
    return os.environ.get("RAILWAY_PRIVATE_DOMAIN") or socket.getfqdn()
