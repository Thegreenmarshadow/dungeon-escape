import pytest


@pytest.fixture
def three_players(client, start_run, finish_run):
    start_run("ana-run-1", player="Ana")
    finish_run("ana-run-1", score=120, level=3)
    start_run("ana-run-2", player="Ana")
    finish_run("ana-run-2", score=40, outcome="quit", level=2)
    start_run("bruno-run-1", player="Bruno")
    finish_run("bruno-run-1", score=300, level=5)
    start_run("bruno-test", player="Bruno", mode="test")
    finish_run("bruno-test", score=999, level=9)
    start_run("carla-run-1", player="Carla")  # still in progress


def test_totals_per_player(client, three_players):
    totals = {row["player_name"]: row for row in client.get("/api/players/totals").json()}
    ana = totals["Ana"]
    assert ana["runs"] == 2
    assert ana["total_score"] == 160
    assert ana["total_time_s"] == 85.0
    assert ana["best_score"] == 120
    assert ana["deepest_level"] == 3
    assert ana["deaths"] == 1
    assert ana["last_played_at"]
    assert totals["Bruno"]["total_score"] == 1299
    assert totals["Carla"] == {**totals["Carla"], "runs": 1, "total_score": 0, "deaths": 0}


def test_totals_are_sorted_by_play_time(client, three_players):
    names = [row["player_name"] for row in client.get("/api/players/totals").json()]
    # Ana and Bruno played 85 s each (two runs of 42.5 s); Carla's run is still at 0.
    assert names == ["Ana", "Bruno", "Carla"]


def test_totals_by_mode_and_player(client, three_players):
    normal = {row["player_name"]: row for row in client.get("/api/players/totals?mode=normal").json()}
    assert normal["Bruno"]["runs"] == 1 and normal["Bruno"]["best_score"] == 300
    only_ana = client.get("/api/players/totals", params={"player": "ana"}).json()
    assert [row["player_name"] for row in only_ana] == ["Ana"]
    assert client.get("/api/players/totals", params={"player": "nobody"}).json() == []


def test_leaderboard_by_player(client, three_players):
    board = client.get("/api/leaderboard", params={"player": "Ana"}).json()
    assert [e["run_id"] for e in board["entries"]] == ["ana-run-1", "ana-run-2"]
    assert board["best_level"] == 3
    assert [e["rank"] for e in board["entries"]] == [1, 2]


def test_stats_by_player(client, three_players):
    stats = client.get("/api/stats", params={"player": "Bruno"}).json()
    assert stats["total_runs"] == 2
    assert stats["best_score"] == 999
    stats = client.get("/api/stats", params={"player": "Bruno", "mode": "normal"}).json()
    assert stats["total_runs"] == 1
    assert stats["total_players"] == 1
