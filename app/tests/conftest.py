import os

import pytest

os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_USER", "test")
os.environ.setdefault("DB_PASSWORD", "test")
os.environ.setdefault("APP_REGION", "eu-west-1")


class StubDatabase:
    """Stands in for the real pool so the API contract can be tested
    without a PostgreSQL instance. Only the behaviour the health
    endpoints rely on is simulated."""

    def __init__(self, settings=None, healthy: bool = True) -> None:
        self.healthy = healthy

    def open(self) -> None:
        pass

    def close(self) -> None:
        pass

    def ping(self) -> bool:
        return self.healthy


@pytest.fixture
def client(monkeypatch):
    from fastapi.testclient import TestClient

    import notes_api.main as main

    monkeypatch.setattr(main, "Database", StubDatabase)
    with TestClient(main.app) as test_client:
        yield test_client
