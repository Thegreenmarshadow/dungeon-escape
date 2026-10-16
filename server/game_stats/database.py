"""SQLite connection handling and schema setup."""

import os
import sqlite3
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parent.parent
SCHEMA_PATH = SERVER_DIR / "schema.sql"
DEFAULT_DB_PATH = SERVER_DIR / "data" / "game.db"
DB_PATH_ENV = "GAME_STATS_DB"


def configured_db_path() -> Path:
    """Database path from GAME_STATS_DB, or server/data/game.db."""
    return Path(os.environ.get(DB_PATH_ENV, DEFAULT_DB_PATH))


def connect(db_path: Path) -> sqlite3.Connection:
    # FastAPI may open the connection (dependency) and use it (endpoint) on
    # different threadpool threads. Each request gets its own connection and
    # never shares it concurrently, so the same-thread check can be disabled.
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


def initialize(db_path: Path) -> None:
    """Create the database file (and its folder) and apply the schema."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = connect(db_path)
    try:
        conn.execute("PRAGMA journal_mode = WAL")
        conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        conn.commit()
    finally:
        conn.close()
