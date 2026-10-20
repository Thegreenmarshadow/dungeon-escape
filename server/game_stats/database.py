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
        _migrate_runs_mode_check(conn)
    finally:
        conn.close()


# Databases created before the "demo" mode existed have this CHECK on runs.mode.
# SQLite cannot alter a CHECK constraint, so the table is rebuilt once.
OLD_MODE_CHECK = "CHECK (mode IN ('normal', 'test'))"
NEW_MODE_CHECK = "CHECK (mode IN ('normal', 'test', 'demo'))"


def _migrate_runs_mode_check(conn: sqlite3.Connection) -> None:
    """Rebuild runs with the new mode CHECK if it still has the old one.

    Follows SQLite's documented procedure for schema changes ALTER TABLE cannot
    make (https://sqlite.org/lang_altertable.html#otheralter): create the new
    table, copy the rows, drop the old one and rename the new one into place.
    Idempotent: a table that already allows "demo" is left untouched.
    """
    table_sql = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'runs'"
    ).fetchone()[0]
    if OLD_MODE_CHECK not in table_sql:
        return
    new_table_sql = table_sql.replace(OLD_MODE_CHECK, NEW_MODE_CHECK).replace(
        "CREATE TABLE runs", "CREATE TABLE runs_new", 1
    )
    # Dropping runs drops its indexes and triggers, so they are recreated after.
    # Automatic indexes (PRIMARY KEY, UNIQUE) have no sql and come back on their own.
    dependents = [
        row[0]
        for row in conn.execute(
            "SELECT sql FROM sqlite_master"
            " WHERE tbl_name = 'runs' AND type IN ('index', 'trigger') AND sql IS NOT NULL"
        )
    ]
    # With foreign keys on, DROP TABLE runs would cascade-delete every event.
    # The pragma is a no-op inside a transaction, so it is set before BEGIN.
    conn.execute("PRAGMA foreign_keys = OFF")
    try:
        conn.execute("BEGIN")
        conn.execute(new_table_sql)
        conn.execute("INSERT INTO runs_new SELECT * FROM runs")
        conn.execute("DROP TABLE runs")
        # events keeps "REFERENCES runs(id)": the name it points to is the one
        # runs_new takes now, so no foreign key needs rewriting.
        conn.execute("ALTER TABLE runs_new RENAME TO runs")
        for sql in dependents:
            conn.execute(sql)
        if conn.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise sqlite3.IntegrityError("foreign key violations after rebuilding runs")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.execute("PRAGMA foreign_keys = ON")
