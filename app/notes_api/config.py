import os
from dataclasses import dataclass, field


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing required environment variable {name}")
    return value


@dataclass(frozen=True)
class Settings:
    """Runtime configuration, resolved once at startup.

    Everything comes from the environment so the same artifact runs
    unchanged in both regions. The instance profile and user data are
    responsible for injecting the right values per region.
    """

    db_host: str = field(default_factory=lambda: _require("DB_HOST"))
    db_port: int = field(default_factory=lambda: int(os.environ.get("DB_PORT", "5432")))
    db_name: str = field(default_factory=lambda: os.environ.get("DB_NAME", "notes"))
    db_user: str = field(default_factory=lambda: _require("DB_USER"))
    db_password: str = field(default_factory=lambda: _require("DB_PASSWORD"))
    # Surfaced in every response so a failover is observable from the client side.
    region: str = field(default_factory=lambda: os.environ.get("APP_REGION", "unknown"))

    @property
    def dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.db_name} "
            f"user={self.db_user} password={self.db_password} "
            f"connect_timeout=3 sslmode=require"
        )


def load_settings() -> Settings:
    return Settings()
