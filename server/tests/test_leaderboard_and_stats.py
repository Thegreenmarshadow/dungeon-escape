import sqlite3

from fastapi.testclient import TestClient


def test_leaderboard_only_has_finished_normal_runs(client: TestClient, start_run, finish_run) -> None:
    start_run("run-normal-low", player="Ana")
    finish_run("run-normal-low", score=120, level=2)
    start_run("run-normal-high", player="Bruno")
    finish_run("run-normal-high", score=300, level=3, outcome="quit")
    start_run("run-test-mode", player="Ana", mode="test")
    finish_run("run-test-mode", score=9999, level=20)
    start_run("run-in-progress", player="Carla")

    board = client.get("/api/leaderboard").json()

    assert [e["run_id"] for e in board["entries"]] == ["run-normal-high", "run-normal-low"]
    assert [e["rank"] for e in board["entries"]] == [1, 2]
    assert board["entries"][0]["player_name"] == "Bruno"
    assert board["best_level"] == 3


def test_leaderboard_excludes_demo_runs(client: TestClient, start_run, finish_run) -> None:
    start_run("run-normal", player="Ana")
    finish_run("run-normal", score=50, level=2)
    start_run("run-demo", player="Bruno", mode="demo")
    finish_run("run-demo", score=10**9, level=99)

    board = client.get("/api/leaderboard").json()

    assert [e["run_id"] for e in board["entries"]] == ["run-normal"]
    assert board["best_level"] == 2


def test_stats_filtered_by_demo_mode_count_only_demo_runs(client: TestClient, start_run, finish_run) -> None:
    start_run("run-stats-normal", player="Ana")
    start_run("run-stats-test", player="Bruno", mode="test")
    start_run("run-stats-demo", player="Carla", mode="demo")
    client.post("/api/runs/run-stats-normal/events", json={"events": [{"seq": 0, "type": "enemy_killed"}]})
    demo_events = [{"seq": 0, "type": "enemy_killed"}, {"seq": 1, "type": "key_picked"}]
    client.post("/api/runs/run-stats-demo/events", json={"events": demo_events})
    finish_run("run-stats-demo", score=70, level=1)

    demo = client.get("/api/stats", params={"mode": "demo"}).json()

    assert demo["total_runs"] == 1
    assert demo["total_players"] == 1
    assert demo["finished_runs"] == 1
    assert demo["total_kills"] == 1
    assert demo["keys_collected"] == 1
    assert demo["best_score"] == 70
    assert client.get("/api/stats").json()["total_runs"] == 3


def test_leaderboard_entries_include_coins_collected(client: TestClient, start_run, finish_run) -> None:
    start_run("run-coins-board")
    coins = [{"seq": 0, "type": "coin_picked", "payload": {"amount": 4}},
             {"seq": 1, "type": "coin_picked", "payload": {"amount": 3}}]
    client.post("/api/runs/run-coins-board/events", json={"events": coins})
    finish_run("run-coins-board", score=50)

    entry = client.get("/api/leaderboard").json()["entries"][0]

    assert entry["coins_collected"] == 7


def test_leaderboard_respects_the_limit(client: TestClient, start_run, finish_run) -> None:
    for i in range(5):
        start_run(f"run-limit-{i}")
        finish_run(f"run-limit-{i}", score=i * 10)

    entries = client.get("/api/leaderboard", params={"limit": 2}).json()["entries"]

    assert [e["score"] for e in entries] == [40, 30]
    assert client.get("/api/leaderboard", params={"limit": 0}).status_code == 422


def test_empty_database_has_empty_leaderboard_and_zero_stats(client: TestClient) -> None:
    assert client.get("/api/leaderboard").json() == {"entries": [], "best_level": 0}
    stats = client.get("/api/stats").json()
    assert stats["total_runs"] == 0
    assert stats["avg_duration_s"] == 0
    assert stats["events_by_type"] == {}
    assert stats["coins_collected"] == 0
    assert stats["coins_spent"] == 0
    assert stats["items_bought"] == 0
    assert stats["items_bought_by_item"] == {}


def test_stats_totals(client: TestClient, start_run, finish_run) -> None:
    start_run("run-stats-1", player="Ana")
    start_run("run-stats-2", player="Bruno", mode="test")
    events = [
        {"seq": 0, "type": "enemy_killed"},
        {"seq": 1, "type": "enemy_killed"},
        {"seq": 2, "type": "key_picked"},
        {"seq": 3, "type": "heart_picked"},
        {"seq": 4, "type": "damage_taken", "payload": {"amount": 2}},
        {"seq": 5, "type": "level_completed", "level": 2},
    ]
    client.post("/api/runs/run-stats-1/events", json={"events": events})
    client.post("/api/runs/run-stats-2/events", json={"events": [{"seq": 0, "type": "enemy_killed"}]})
    finish_run("run-stats-1", score=120, level=2)

    stats = client.get("/api/stats").json()
    normal_only = client.get("/api/stats", params={"mode": "normal"}).json()

    assert stats["total_runs"] == 2
    assert stats["total_players"] == 2
    assert stats["finished_runs"] == 1
    assert stats["total_kills"] == 3
    assert stats["keys_collected"] == 1
    assert stats["hearts_collected"] == 1
    assert stats["damage_taken"] == 2
    assert stats["levels_completed"] == 1
    assert stats["avg_duration_s"] == 42.5
    assert stats["best_level"] == 2
    assert stats["best_score"] == 120
    assert stats["events_by_type"]["enemy_killed"] == 3
    assert normal_only["total_kills"] == 2


def test_stats_damage_keeps_half_hearts(client: TestClient, start_run) -> None:
    # Old runs report whole hearts; since the half-heart change a hit can take
    # 0.5 or 1.5 hearts. Both add up in the same unit.
    start_run("run-halves-1", player="Ana")
    events = [
        {"seq": 0, "type": "damage_taken", "payload": {"amount": 1, "lives": 2}},
        {"seq": 1, "type": "damage_taken", "payload": {"amount": 0.5, "lives": 1.5}},
        {"seq": 2, "type": "damage_taken", "payload": {"amount": 1.5, "lives": 0}},
    ]
    client.post("/api/runs/run-halves-1/events", json={"events": events})

    assert client.get("/api/stats").json()["damage_taken"] == 3.0


def test_stats_coin_and_shop_totals(client: TestClient, start_run) -> None:
    start_run("run-shop-1", player="Ana")
    start_run("run-shop-2", player="Bruno", mode="test")
    events = [
        {"seq": 0, "type": "coin_picked", "payload": {"amount": 12}},
        {"seq": 1, "type": "coin_picked", "payload": {"amount": 30}},
        {"seq": 2, "type": "item_bought", "payload": {"item": "damage", "price": 10}},
        {"seq": 3, "type": "item_bought", "payload": {"item": "life", "price": 6}},
        {"seq": 4, "type": "item_bought", "payload": {"item": "damage", "price": 20}},
    ]
    client.post("/api/runs/run-shop-1/events", json={"events": events})
    test_events = [
        {"seq": 0, "type": "coin_picked", "payload": {"amount": 5}},
        {"seq": 1, "type": "item_bought", "payload": {"item": "life", "price": 6}},
    ]
    client.post("/api/runs/run-shop-2/events", json={"events": test_events})

    stats = client.get("/api/stats").json()
    normal_only = client.get("/api/stats", params={"mode": "normal"}).json()

    assert stats["coins_collected"] == 47
    assert stats["coins_spent"] == 42
    assert stats["items_bought"] == 4
    assert stats["items_bought_by_item"] == {"damage": 2, "life": 2}
    assert normal_only["coins_collected"] == 42
    assert normal_only["coins_spent"] == 36
    assert normal_only["items_bought_by_item"] == {"damage": 2, "life": 1}


def test_malformed_coin_payloads_count_as_zero(client: TestClient, start_run, tmp_path) -> None:
    start_run("run-bad-coins")
    events = [
        {"seq": 0, "type": "coin_picked", "payload": {"amount": 5}},
        {"seq": 1, "type": "coin_picked"},
        {"seq": 2, "type": "coin_picked", "payload": {"amount": "lots"}},
        {"seq": 3, "type": "coin_picked", "payload": {"amount": None}},
        {"seq": 4, "type": "coin_picked", "payload": {"amount": -3}},
        {"seq": 5, "type": "coin_picked", "payload": {"amount": True}},
        {"seq": 6, "type": "coin_picked", "payload": {"amount": 2.0}},
        {"seq": 7, "type": "item_bought", "payload": {"price": "free"}},
        {"seq": 8, "type": "item_bought", "payload": {"item": 3, "price": 6}},
    ]
    client.post("/api/runs/run-bad-coins/events", json={"events": events})
    # A row whose payload is not even JSON (written outside the API).
    with sqlite3.connect(tmp_path / "test.db") as conn:
        conn.execute(
            "INSERT INTO events (run_id, seq, type, payload, created_at) VALUES (?, ?, ?, ?, ?)",
            ("run-bad-coins", 9, "coin_picked", "{not json", "2026-10-16T00:00:00Z"),
        )

    stats = client.get("/api/stats").json()
    run = client.get("/api/runs/run-bad-coins").json()

    assert stats["coins_collected"] == 7
    assert stats["coins_spent"] == 6
    assert stats["items_bought"] == 2
    assert stats["items_bought_by_item"] == {"unknown": 2}
    assert (run["coins_collected"], run["coins_spent"]) == (7, 6)


def test_health_and_web_ui_are_served(client: TestClient) -> None:
    assert client.get("/api/health").json() == {"status": "ok"}
    page = client.get("/")
    assert page.status_code == 200
    assert "<title>" in page.text
