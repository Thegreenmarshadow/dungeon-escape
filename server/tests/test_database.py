import sqlite3
import threading
from pathlib import Path

import pytest

from game_stats import database


def test_connection_can_be_used_from_another_thread(tmp_path: Path) -> None:
    # FastAPI opens the connection in the dependency and may run the endpoint
    # on a different threadpool thread.
    db_path = tmp_path / "threads.db"
    database.initialize(db_path)
    conn = database.connect(db_path)
    errors: list[Exception] = []

    def use_connection() -> None:
        try:
            conn.execute("SELECT COUNT(*) FROM runs").fetchone()
        except Exception as error:  # noqa: BLE001 - the test reports any failure
            errors.append(error)

    worker = threading.Thread(target=use_connection)
    worker.start()
    worker.join()
    conn.close()

    assert errors == []


def _create_old_database(db_path: Path) -> None:
    """A database as created before the "demo" mode, with one run and one event."""
    schema = database.SCHEMA_PATH.read_text(encoding="utf-8")
    assert database.NEW_MODE_CHECK in schema
    conn = database.connect(db_path)
    conn.executescript(schema.replace(database.NEW_MODE_CHECK, database.OLD_MODE_CHECK))
    with conn:
        conn.execute("INSERT INTO players (id, name, created_at) VALUES (1, 'Ana', '2026-10-01T00:00:00Z')")
        conn.execute(
            "INSERT INTO runs (id, player_id, mode, started_at, score, outcome)"
            " VALUES ('old-run-1', 1, 'test', '2026-10-01T00:00:00Z', 120, 'died')"
        )
        conn.execute(
            "INSERT INTO events (run_id, seq, type, created_at)"
            " VALUES ('old-run-1', 0, 'enemy_killed', '2026-10-01T00:00:00Z')"
        )
    conn.close()


def _insert_demo_run(conn: sqlite3.Connection, run_id: str) -> None:
    with conn:
        conn.execute(
            "INSERT INTO runs (id, player_id, mode, started_at) VALUES (?, 1, 'demo', '2026-10-02T00:00:00Z')",
            (run_id,),
        )


def test_old_database_is_migrated_to_accept_demo_runs(tmp_path: Path) -> None:
    db_path = tmp_path / "old.db"
    _create_old_database(db_path)
    conn = database.connect(db_path)
    with pytest.raises(sqlite3.IntegrityError):
        _insert_demo_run(conn, "demo-before")
    conn.close()

    database.initialize(db_path)

    conn = database.connect(db_path)
    _insert_demo_run(conn, "demo-after")
    run = conn.execute("SELECT mode, score, outcome FROM runs WHERE id = 'old-run-1'").fetchone()
    events = conn.execute("SELECT run_id, type FROM events").fetchall()
    indexes = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'index'")}
    events_sql = conn.execute("SELECT sql FROM sqlite_master WHERE name = 'events'").fetchone()[0]
    assert tuple(run) == ("test", 120, "died")
    assert [tuple(e) for e in events] == [("old-run-1", "enemy_killed")]
    assert {"idx_runs_score", "idx_runs_player"} <= indexes
    assert "REFERENCES runs(id)" in events_sql
    assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
    # The cascade from runs to events still works after the rebuild.
    with conn:
        conn.execute("DELETE FROM runs WHERE id = 'old-run-1'")
    assert conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] == 0
    conn.close()


def test_migration_runs_only_once(tmp_path: Path) -> None:
    db_path = tmp_path / "old.db"
    _create_old_database(db_path)
    database.initialize(db_path)
    conn = database.connect(db_path)
    _insert_demo_run(conn, "demo-1")
    schema_before = conn.execute("SELECT type, name, sql FROM sqlite_master ORDER BY name").fetchall()
    conn.close()

    database.initialize(db_path)

    conn = database.connect(db_path)
    schema_after = conn.execute("SELECT type, name, sql FROM sqlite_master ORDER BY name").fetchall()
    run_ids = [row[0] for row in conn.execute("SELECT id FROM runs ORDER BY id")]
    conn.close()
    assert [tuple(r) for r in schema_after] == [tuple(r) for r in schema_before]
    assert run_ids == ["demo-1", "old-run-1"]


def test_initialize_creates_the_folder_and_is_idempotent(tmp_path: Path) -> None:
    db_path = tmp_path / "nested" / "game.db"

    database.initialize(db_path)
    database.initialize(db_path)

    conn = database.connect(db_path)
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    conn.close()
    assert {"players", "runs", "events"} <= tables
