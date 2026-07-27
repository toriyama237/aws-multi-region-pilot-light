from contextlib import contextmanager
from typing import Iterator

from psycopg import Connection
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import Settings

SCHEMA = """
CREATE TABLE IF NOT EXISTS notes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT NOT NULL,
    body        TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


class Database:
    """Thin wrapper around a psycopg connection pool.

    The pool is sized small on purpose: the instances behind the ALB are
    t3.micro and RDS db.t3.micro caps out around 80 connections. Keeping
    max_size low avoids exhausting the promoted replica right after a
    failover, when every instance reconnects at once.
    """

    def __init__(self, settings: Settings) -> None:
        self._pool = ConnectionPool(
            conninfo=settings.dsn,
            min_size=1,
            max_size=5,
            open=False,
        )

    def open(self) -> None:
        self._pool.open()
        with self.connection() as conn:
            # During a failover the pilot light instances boot while the
            # local database is still a read replica. Any DDL, even
            # CREATE TABLE IF NOT EXISTS, aborts in a read-only
            # transaction and would crash-loop the service until the
            # promotion completes. Skipping schema init on a replica
            # lets the instance come up, serve its health endpoint, and
            # start writing the moment the promotion lands.
            in_recovery = conn.execute("SELECT pg_is_in_recovery()").fetchone()
            if not in_recovery["pg_is_in_recovery"]:
                conn.execute(SCHEMA)

    def close(self) -> None:
        self._pool.close()

    @contextmanager
    def connection(self) -> Iterator[Connection]:
        with self._pool.connection() as conn:
            conn.row_factory = dict_row
            yield conn

    def ping(self) -> bool:
        """Cheap readiness probe used by the health endpoint.

        A plain SELECT 1 works against both a writable primary and a
        read replica, so the check stays meaningful in either region.
        """
        try:
            with self.connection() as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False
