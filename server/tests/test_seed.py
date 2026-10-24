import random
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from game_stats import level_maps, seed
from game_stats.app import create_app


@pytest.fixture(scope="module")
def seeded(tmp_path_factory: pytest.TempPathFactory) -> Iterator[tuple[Path, int, TestClient]]:
    """One seeded database shared by the tests of this module (read only)."""
    db_path = tmp_path_factory.mktemp("seed") / "seed.db"
    count = seed.seed(db_path)
    with TestClient(create_app(db_path)) as client:
        yield db_path, count, client


def test_seed_creates_players_and_runs_of_every_kind(seeded):
    _, count, client = seeded
    totals = client.get("/api/players/totals").json()
    runs = client.get("/api/runs", params={"limit": 500}).json()

    assert {row["player_name"] for row in totals} == set(seed.SAMPLE_PLAYERS)
    assert len(runs) == count == sum(runs for runs, _ in seed.SAMPLE_PLAYERS.values())
    assert {run["mode"] for run in runs} == {"normal", "test", "demo"}
    assert {run["outcome"] for run in runs} == {"died", "quit", "in_progress"}
    assert all(run["level_tracks"] > 0 for run in runs), "every run has routes to draw"
    assert client.get("/api/leaderboard").json()["entries"]


def test_run_events_match_the_run_result(seeded):
    _, _, client = seeded
    for run in client.get("/api/runs", params={"limit": 500}).json():
        detail = client.get(f"/api/runs/{run['id']}").json()
        types = [event["type"] for event in detail["events"]]
        kills = types.count("enemy_killed")
        completed = types.count("level_completed")
        if run["outcome"] == "in_progress":
            continue
        assert run["enemies_killed"] == kills
        assert run["score"] == kills * seed.POINTS_PER_KILL + completed * seed.POINTS_PER_LEVEL
        assert types[-1] == ("player_died" if run["outcome"] == "died" else "run_quit")
        assert run["coins_spent"] <= run["coins_collected"]


def test_level_files_match_the_run_events(seeded):
    _, _, client = seeded
    run = next(r for r in client.get("/api/runs", params={"limit": 500}).json() if r["outcome"] == "died")
    events = client.get(f"/api/runs/{run['id']}").json()["events"]
    levels = client.get(f"/api/runs/{run['id']}/levels").json()

    assert [level["level"] for level in levels] == list(range(1, run["level_reached"] + 1))
    assert levels[-1]["outcome"] == "died"
    assert all(level["outcome"] == "completed" for level in levels[:-1])
    for level in levels:
        kills = sum(1 for e in events if e["type"] == "enemy_killed" and e["level"] == level["level"])
        assert level["summary"]["kills"] == kills


def test_routes_stay_on_the_floor(seeded):
    _, _, client = seeded
    runs = client.get("/api/runs", params={"limit": 500}).json()
    for run in runs[:12]:
        for level in client.get(f"/api/runs/{run['id']}/levels").json():
            level_map = level["map"]
            width, _ = level_map["size"]
            cells = level_map["cells"]
            for _, x, y in level["path"]:
                cx, cy = level_maps.world_to_cell(level_map, x, y)
                assert cells[cy * width + cx] == "1", f"{run['id']} level {level['level']} leaves the floor"


def test_analytics_have_heatmaps_and_warnings(seeded):
    _, _, client = seeded
    analytics = client.get("/api/analytics").json()

    assert len(analytics["heatmaps"]) >= 6
    assert any(row["attempts"] >= analytics["thresholds"]["min_attempts"] for row in analytics["levels"])
    assert any("muere" in line for line in analytics["insights"])
    assert any(point["planned"] is not None for point in analytics["chart"])
    assert set(analytics["options"]["versions"]) == {seed.OLD_VERSION, seed.NEW_VERSION}


def test_stats_include_coins_and_purchases(seeded):
    _, _, client = seeded
    stats = client.get("/api/stats").json()

    assert stats["coins_collected"] > stats["coins_spent"] > 0
    assert {"damage", "life"} <= set(stats["items_bought_by_item"])
    assert stats["damage_taken"] > 0 and stats["keys_collected"] > 0


def test_sample_maps_connect_start_key_and_door():
    for name, data in seed.load_maps().items():
        for variant in (data, seed.mirrored(data)):
            sample = seed.SampleMap.from_data(variant)
            start, key, door = sample.cell("start"), sample.cell("key"), sample.cell("door")
            assert sample.is_floor(start) and sample.is_floor(key) and sample.is_floor(door), name
            assert sample.route(start, key) and sample.route(key, door), name


def test_mirrored_map_round_trips():
    data = seed.load_maps()["cavern_a"]

    twice = seed.mirrored(seed.mirrored(data))

    assert level_maps.decode_floor(twice) == level_maps.decode_floor(data)
    assert twice["door"] == data["door"] and twice["rooms"] == data["rooms"]


def test_encode_floor_is_the_inverse_of_decode():
    data = {"size": [3, 2], "floor": "3,2,1"}
    assert seed.encode_floor(level_maps.decode_floor(data)) == "3,2,1"
    assert seed.encode_floor(bytearray([1, 1, 0])) == "0,2,1"


def test_play_level_reaches_the_outcome():
    sample = seed.SampleMap.from_data(seed.load_maps()["level_1"])

    died = seed.play_level(random.Random(1), sample, 3, 3, "sword", 1.0, "died")
    completed = seed.play_level(random.Random(2), sample, 1, 3, "sword", 1.0, "completed")

    assert died.lives == 0 and died.events[-1]["type"] == "death"
    assert completed.lives > 0
    assert completed.events[-1] == {**completed.events[-1], "type": "door", "state": "escaped"}
    assert any(event["type"] == "key" for event in completed.events)
    times = [sample[0] for sample in completed.path]
    assert times == sorted(times)


def test_seed_is_deterministic_and_removable(tmp_path):
    first, second = tmp_path / "a.db", tmp_path / "b.db"
    seed.seed(first)
    seed.seed(second)
    with TestClient(create_app(first)) as a, TestClient(create_app(second)) as b:
        scores_a = [(r["id"], r["score"]) for r in a.get("/api/runs", params={"limit": 500}).json()]
        scores_b = [(r["id"], r["score"]) for r in b.get("/api/runs", params={"limit": 500}).json()]
        assert sorted(scores_a) == sorted(scores_b)
        a.post("/api/runs", json={"id": "real-run-01", "player_name": "Ana"})

    removed = seed.remove(first)

    assert removed == len(scores_a)
    with TestClient(create_app(first)) as a:
        assert [r["id"] for r in a.get("/api/runs").json()] == ["real-run-01"]
        assert [p["name"] for p in a.get("/api/players").json()] == ["Ana"], "a sample name with real runs stays"
        assert a.get("/api/analytics").json()["files"] == 0
