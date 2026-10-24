import json
import sqlite3
from pathlib import Path

from game_stats import database
from game_stats.models import MAX_LEVEL_BYTES


def test_upload_stores_the_level_once(client, start_run, level_file, upload_level):
    start_run("run-levels-1")
    data = level_file("normal_level_2_died")

    first = upload_level("run-levels-1", data)
    assert first == {"run_id": "run-levels-1", "level": 2, "attempt": 1, "created": True}
    # A retried upload (the game never got the answer) changes nothing.
    again = upload_level("run-levels-1", data, expected=200)
    assert again["created"] is False

    levels = client.get("/api/runs/run-levels-1/levels").json()
    assert len(levels) == 1
    assert levels[0]["outcome"] == "died"
    assert levels[0]["mode"] == "normal"
    assert levels[0]["game_version"] == "0.9.0"


def test_upload_needs_the_run_first(client, level_file, upload_level):
    body = upload_level("never-started", level_file("normal_level_2_died"), expected=404)
    assert "not found" in body["detail"]


def test_attempts_of_the_same_level_are_kept_apart(client, start_run, level_file, upload_level):
    start_run("run-levels-2")
    upload_level("run-levels-2", level_file("normal_level_2_died"))
    upload_level("run-levels-2", level_file("normal_level_2_attempt_2"))
    upload_level("run-levels-2", level_file("normal_level_1_completed"))

    levels = client.get("/api/runs/run-levels-2/levels").json()
    assert [(row["level"], row["attempt"]) for row in levels] == [(1, 1), (2, 1), (2, 2)]


def test_listed_level_has_the_decoded_map_and_a_summary(client, start_run, level_file, upload_level):
    start_run("run-levels-3")
    data = level_file("normal_level_2_died")
    upload_level("run-levels-3", data)

    level = client.get("/api/runs/run-levels-3/levels").json()[0]
    width, height = data["map"]["size"]
    cells = level["map"]["cells"]
    assert len(cells) == width * height
    assert set(cells) <= {"0", "1", "2"}
    start_x, start_y = data["map"]["start"]
    assert cells[start_y * width + start_x] == "1", "the start cell is floor"
    assert level["map"]["door"] == data["map"]["door"]
    assert level["label"] == f"Nivel 2 · semilla {data['level_seed']}"
    assert len(level["path"]) == len(data["path"])
    assert level["summary"]["damage_by_source"] == [{"source": "spikes", "label": "picos", "count": 1}]
    assert level["summary"]["deaths_by_cause"] == [{"source": "spikes", "label": "picos", "count": 1}]
    assert level["summary"]["kills"] == 1
    assert level["summary"]["keys"] == 1


def test_unknown_fields_are_kept(client, start_run, level_file, upload_level, tmp_path):
    start_run("run-levels-4")
    upload_level("run-levels-4", level_file("normal_level_2_died", difficulty_index=7.5, future_field={"a": 1}))

    conn = sqlite3.connect(tmp_path / "test.db")
    row = conn.execute("SELECT data, difficulty_index FROM level_tracks").fetchone()
    stored = json.loads(row[0])
    assert stored["future_field"] == {"a": 1}
    assert stored["level_seed"] == "7420309529871677574", "the 64-bit seed stays text"
    assert row[1] == 7.5


def test_bad_shapes_are_rejected(client, start_run, level_file, upload_level):
    start_run("run-levels-5")
    good = level_file("normal_level_2_died")
    upload_level("run-levels-5", {**good, "outcome": "in_progress"}, expected=422)
    upload_level("run-levels-5", {**good, "level": 0}, expected=422)
    upload_level("run-levels-5", {k: v for k, v in good.items() if k != "map"}, expected=422)
    upload_level("run-levels-5", {**good, "map": {**good["map"], "floor": "1,2,<script>"}}, expected=422)
    upload_level("run-levels-5", {**good, "path": [[0.0, 1.0]]}, expected=422)
    upload_level("run-levels-5", {**good, "events": [{"t": 1.0, "type": "Not Valid"}]}, expected=422)

    not_json = client.post(
        "/api/runs/run-levels-5/levels", content=b"{nope", headers={"Content-Type": "application/json"}
    )
    assert not_json.status_code == 400
    assert client.post("/api/runs/run-levels-5/levels", json=[1, 2]).status_code == 422
    assert client.get("/api/runs/run-levels-5/levels").json() == []


def test_too_large_uploads_are_rejected(client, start_run, level_file):
    start_run("run-levels-6")
    data = level_file("normal_level_2_died", padding="x" * MAX_LEVEL_BYTES)
    response = client.post("/api/runs/run-levels-6/levels", json=data)
    assert response.status_code == 413


def test_levels_of_an_unknown_run(client):
    assert client.get("/api/runs/nope-nope/levels").status_code == 404


def test_deleting_a_run_deletes_its_levels(client, start_run, level_file, upload_level, tmp_path):
    start_run("run-levels-7")
    upload_level("run-levels-7", level_file("normal_level_2_died"))
    conn = database.connect(Path(tmp_path / "test.db"))
    with conn:
        conn.execute("DELETE FROM runs WHERE id = 'run-levels-7'")
    assert conn.execute("SELECT COUNT(*) FROM level_tracks").fetchone()[0] == 0
    conn.close()


def test_schema_is_reapplied_without_losing_levels(client, start_run, level_file, upload_level, tmp_path):
    start_run("run-levels-8")
    upload_level("run-levels-8", level_file("normal_level_2_died"))
    database.initialize(tmp_path / "test.db")
    assert len(client.get("/api/runs/run-levels-8/levels").json()) == 1
