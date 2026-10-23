import pytest


@pytest.fixture
def ana_runs(client, start_run, finish_run):
    start_run("ana-run-1", player="Ana", started_at="2026-10-01T10:00:00Z")
    finish_run("ana-run-1", score=120, level=3)
    start_run("ana-run-2", player="Ana", started_at="2026-10-02T10:00:00Z")
    finish_run("ana-run-2", score=40, outcome="quit", level=2)
    start_run("ana-test", player="Ana", mode="test", started_at="2026-10-03T10:00:00Z")
    finish_run("ana-test", score=999, level=9)
    start_run("ana-live", player="Ana", started_at="2026-10-04T10:00:00Z")  # still in progress
    start_run("bruno-run-1", player="Bruno")
    finish_run("bruno-run-1", score=300, level=5)
    return client.get("/api/runs/ana-run-1").json()["player_id"]


def test_profile_sums_every_run(client, ana_runs):
    profile = client.get(f"/api/players/{ana_runs}").json()

    assert profile["player"]["name"] == "Ana"
    totals = profile["totals"]
    assert totals["runs"] == 4
    assert totals["total_score"] == 120 + 40 + 999
    assert totals["total_time_s"] == 127.5
    assert totals["best_score"] == 999
    assert totals["deepest_level"] == 9
    assert totals["deaths"] == 2
    assert profile["first_played_at"] == "2026-10-01T10:00:00Z"


def test_profile_lists_the_runs_newest_first(client, ana_runs):
    profile = client.get(f"/api/players/{ana_runs}").json()

    assert [run["id"] for run in profile["runs"]] == ["ana-live", "ana-test", "ana-run-2", "ana-run-1"]
    assert all(run["player_name"] == "Ana" for run in profile["runs"])
    limited = client.get(f"/api/players/{ana_runs}", params={"limit": 1}).json()
    assert [run["id"] for run in limited["runs"]] == ["ana-live"]
    assert limited["totals"]["runs"] == 4, "the limit only cuts the list"


def test_best_run_is_the_one_the_leaderboard_ranks(client, ana_runs):
    # The test run has a higher score but only normal finished runs compete.
    best = client.get(f"/api/players/{ana_runs}").json()["best_run"]

    assert best["id"] == "ana-run-1"
    assert best["score"] == 120


def test_profile_totals_per_mode(client, ana_runs):
    by_mode = client.get(f"/api/players/{ana_runs}").json()["totals_by_mode"]

    assert set(by_mode) == {"normal", "test"}
    assert by_mode["normal"]["runs"] == 3
    assert by_mode["normal"]["total_score"] == 160
    assert by_mode["test"]["best_score"] == 999


def test_player_without_runs_has_zero_totals(client):
    player = client.post("/api/players", json={"name": "Nadie"}).json()

    profile = client.get(f"/api/players/{player['id']}").json()

    assert profile["totals"]["runs"] == 0
    assert profile["totals"]["total_score"] == 0
    assert profile["totals"]["last_played_at"] is None
    assert profile["totals_by_mode"] == {}
    assert profile["best_run"] is None
    assert profile["runs"] == []


def test_leaderboard_entries_link_to_the_player(client, ana_runs):
    entries = client.get("/api/leaderboard").json()["entries"]

    ana = next(entry for entry in entries if entry["player_name"] == "Ana")
    assert ana["player_id"] == ana_runs


def test_unknown_player_is_404(client):
    assert client.get("/api/players/999").status_code == 404


def test_totals_route_still_wins_over_the_player_id(client, ana_runs):
    assert client.get("/api/players/totals").status_code == 200


def test_runs_count_their_stored_level_files(client, start_run, level_file, upload_level):
    start_run("run-with-levels")
    start_run("run-without-levels")
    upload_level("run-with-levels", level_file("normal_level_1_completed"))
    upload_level("run-with-levels", level_file("normal_level_2_died"))

    runs = {run["id"]: run for run in client.get("/api/runs").json()}

    assert runs["run-with-levels"]["level_tracks"] == 2
    assert runs["run-without-levels"]["level_tracks"] == 0
    assert client.get("/api/runs/run-with-levels").json()["level_tracks"] == 2
