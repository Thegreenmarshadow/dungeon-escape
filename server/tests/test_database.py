import threading
from pathlib import Path

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


def test_initialize_creates_the_folder_and_is_idempotent(tmp_path: Path) -> None:
    db_path = tmp_path / "nested" / "game.db"

    database.initialize(db_path)
    database.initialize(db_path)

    conn = database.connect(db_path)
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    conn.close()
    assert {"players", "runs", "events"} <= tables
