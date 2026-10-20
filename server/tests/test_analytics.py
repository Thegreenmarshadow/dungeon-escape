import pytest

from game_stats import analytics, level_maps


def _level(level=2, outcome="completed", duration=60.0, events=(), mode="normal", **extra):
    return {
        "level": level,
        "mode": mode,
        "outcome": outcome,
        "duration_s": duration,
        "events": list(events),
        "weapons_used": ["sword"],
        "map": {"size": [4, 3], "cell_px": 16, "origin": [0, 0], "floor": "5,2,2,2,1"},
        **extra,
    }


def _damage(source, amount=1, x=24.0, y=24.0):
    return {"t": 1.0, "type": "damage", "x": x, "y": y, "amount": amount, "source": source}


def _death(cause, x=24.0, y=24.0):
    return {"t": 2.0, "type": "death", "x": x, "y": y, "cause": cause, "final": True}


# --- maps -----------------------------------------------------------------------


def test_floor_decoding_matches_the_game():
    level_map = {"size": [3, 2], "floor": "3,2,1"}
    assert list(level_maps.decode_floor(level_map)) == [0, 0, 0, 1, 1, 0]
    # The first run may be 0 (the grid starts with floor); runs past the end are cut.
    assert list(level_maps.decode_floor({"size": [2, 2], "floor": "0,3,9"})) == [1, 1, 1, 0]
    assert list(level_maps.decode_floor({"size": [2, 1], "floor": ""})) == [0, 0]


def test_walls_are_non_floor_cells_touching_floor():
    # 4x3 grid with floor at (1,1) and (2,1).
    grid = level_maps.cell_grid({"size": [4, 3], "floor": "5,2,5"})
    assert grid == "2222" "2112" "2222"
    far = level_maps.cell_grid({"size": [5, 1], "floor": "0,1,4"})
    assert far == "12000"


def test_world_to_cell_uses_origin_and_cell_size():
    level_map = {"size": [10, 10], "cell_px": 16, "origin": [32, -16]}
    assert level_maps.world_to_cell(level_map, 32, -16) == (0, 0)
    assert level_maps.world_to_cell(level_map, 47.9, 0) == (0, 1)
    assert level_maps.world_to_cell(level_map, 31, 0) == (-1, 1)


# --- per-level stats ----------------------------------------------------------------


def test_level_stats_follow_level_stats_gd():
    levels = [
        _level(2, "died", 30.0, [_damage("spikes", 2), _death("spikes")]),
        _level(2, "completed", 90.0, [_damage("Skeleton")]),
        _level(2, "abandoned", 0.0),
        _level(3, "died", 60.0, [_damage("Archer", 3), _death("Archer")]),
        _level(3, "in_progress", 60.0),
        _level(1, "died", 10.0, [_death("spikes")], mode="demo"),
    ]
    rows = analytics.level_stats(levels)
    assert [row["level"] for row in rows] == [2, 3], "demo and in-progress files are left out"
    two, three = rows
    assert (two["attempts"], two["completed"], two["died"], two["abandoned"]) == (3, 1, 1, 1)
    assert two["completion_rate"] == pytest.approx(1 / 3)
    assert two["mean_time_s"] == pytest.approx(40.0)
    assert two["damage_total"] == 3
    assert two["damage_per_min"] == pytest.approx(3 / 2.0)
    assert two["damage_by_source"] == {"spikes": 2, "Skeleton": 1}
    assert two["top_death_cause"] == "spikes"
    assert three["damage_per_min"] == pytest.approx(3.0)
    # Level 3: 1 death per attempt (max) and 3 damage/min (max) -> 1.0.
    assert three["measured_difficulty"] == pytest.approx(1.0)
    # Level 2: (1/3) / 1 * 0.5 + 1.5 / 3 * 0.5.
    assert two["measured_difficulty"] == pytest.approx(0.5 / 3 + 0.25)


def test_empty_source_is_unknown_and_ties_go_alphabetical():
    rows = analytics.level_stats([_level(2, "died", 10, [_death(""), _death("b"), _death("a")])])
    assert rows[0]["deaths_by_cause"] == {"unknown": 1, "b": 1, "a": 1}
    assert analytics.top_death_cause(rows[0])["cause"] == "a"


def test_demo_counts_when_it_is_asked_for():
    rows = analytics.level_stats([_level(1, "died", 10, mode="demo")], excluded_modes=())
    assert rows[0]["attempts"] == 1


# --- warnings -------------------------------------------------------------------------


def test_warnings_use_the_insights_gd_rules():
    levels = []
    # Level 6: 5 attempts, 1 minute each, 1 damage each, nothing else.
    levels += [_level(6, "completed", 60.0, [_damage("Skeleton")]) for _ in range(5)]
    # Level 7: 4 deaths of 5 (80 %), 3 by spikes; 3 minutes each; lots of damage.
    levels += [_level(7, "died", 180.0, [_damage("spikes", 10), _death("spikes")]) for _ in range(3)]
    levels += [_level(7, "died", 180.0, [_damage("Archer", 10), _death("Archer")])]
    levels += [_level(7, "abandoned", 180.0)]
    lines = analytics.insights(analytics.level_stats(levels))
    assert lines == [
        "Nivel 7: 80 % muere, el 75 % por picos",
        "Nivel 7: tiempo medio 3× el del nivel 6",
        "Nivel 7: daño por minuto 2.7× el del nivel 6",
    ]


def test_no_warnings_below_the_minimum_attempts():
    lines = analytics.insights(analytics.level_stats([_level(2, "died", 10, [_death("x")])] * 4))
    assert lines == ["Sin avisos todavía: ningún nivel llega a 5 intentos (hay 1 niveles con menos)."]
    assert analytics.insights([]) == []


def test_abandon_warning_and_unnamed_cause():
    levels = [_level(4, "abandoned", 30.0) for _ in range(2)] + [_level(4, "died", 30.0, [_death("a")]) for _ in range(2)]
    levels += [_level(4, "completed", 30.0)]
    lines = analytics.insights(analytics.level_stats(levels))
    # 40 % die (2 deaths: too few to name a cause) and 40 % abandon.
    assert lines == ["Nivel 4: 40 % muere", "Nivel 4: 40 % abandona sin terminar"]


def test_ratios_are_formatted_like_the_game():
    assert analytics._times(3.04) == "3×"
    assert analytics._times(2.46) == "2.5×"
    assert analytics._pct(0.125) == 13, "halves round away from zero like roundi"


# --- difficulty chart --------------------------------------------------------------------


def test_chart_normalizes_the_planned_index_and_leaves_gaps():
    levels = [
        _level(2, "died", 60.0, [_death("x")], difficulty_index=4.0),
        _level(3, "completed", 60.0, difficulty_index=8.0),
        _level(1, "completed", 60.0, difficulty_index=None),
    ]
    rows = analytics.level_stats(levels)
    points = analytics.chart_rows(rows, analytics.planned_indexes(levels))
    assert [p["level"] for p in points] == list(range(1, 11)), "at least up to level 10"
    by_level = {p["level"]: p for p in points}
    assert by_level[1]["planned"] is None, "the hand-made level has no planned index"
    assert by_level[2]["planned"] == pytest.approx(0.5)
    assert by_level[3]["planned"] == pytest.approx(1.0)
    # Most deaths per attempt (0.5) and no damage anywhere (0).
    assert by_level[2]["measured"] == pytest.approx(0.5)
    assert by_level[3]["measured"] == pytest.approx(0.0)
    assert by_level[5]["measured"] is None and by_level[5]["attempts"] == 0


# --- heatmaps ------------------------------------------------------------------------------


def test_time_weights_each_sample_by_the_gap_to_the_next():
    data = _level(duration=3.0, path=[[0.0, 24.0, 24.0], [0.5, 24.0, 24.0], [2.0, 40.0, 24.0]])
    grid = analytics.heat_grid(data["map"], [data], analytics.LAYER_TIME)
    # Cell (1,1) = index 5: 0.5 s + 1.5 s; cell (2,1) = index 6: until the end, 1 s.
    assert grid == {5: pytest.approx(2.0), 6: pytest.approx(1.0)}


def test_heatmaps_group_runs_on_the_same_map(level_file):
    first = level_file("normal_level_1_completed")
    second = level_file("normal_level_1_completed", run_id="other")
    died = level_file("normal_level_2_died")
    demo = level_file("demo_level_1_revive")
    groups = analytics.heatmaps([died, first, demo, second])
    assert [g["label"] for g in groups][0] == "Nivel 1 (hecho a mano)"
    assert groups[0]["attempts"] == 2, "level 1 always shares its map"
    labels = {g["label"] for g in groups}
    assert "Demo" in labels and f"Nivel 2 · semilla {died['level_seed']}" in labels
    level_two = next(g for g in groups if g["level"] == 2)
    assert level_two["totals"]["deaths"] == 1
    assert level_two["totals"]["damage"] == 1
    assert level_two["totals"]["time"] == pytest.approx(died["duration_s"])
    width = level_two["map"]["size"][0]
    death = next(e for e in died["events"] if e["type"] == "death")
    cell = level_maps.world_to_cell(died["map"], death["x"], death["y"])
    assert level_two["layers"]["deaths"] == [[cell[1] * width + cell[0], 1.0]]


def test_same_level_label_on_different_maps_is_numbered():
    a = _level(5, map={"size": [2, 1], "floor": "0,2"})
    b = _level(5, map={"size": [2, 1], "floor": "1,1"})
    labels = [g["label"] for g in analytics.group_by_map([a, b, a])]
    assert labels == ["Nivel 5", "Nivel 5 (mapa 2)"]


# --- API -------------------------------------------------------------------------------------


def test_analytics_endpoint_filters_by_player_level_version_and_mode(
    client, start_run, level_file, upload_level
):
    start_run("ana-run-1", player="Ana")
    start_run("bruno-run-1", player="Bruno")
    start_run("ana-demo-1", player="Ana", mode="demo")
    upload_level("ana-run-1", level_file("normal_level_1_completed"))
    upload_level("ana-run-1", level_file("normal_level_2_died", difficulty_index=6.0))
    upload_level("bruno-run-1", level_file("normal_level_2_attempt_2", game_version="1.0.0"))
    upload_level("ana-demo-1", level_file("demo_level_1_revive"))

    everything = client.get("/api/analytics").json()
    assert everything["files"] == 4
    assert [row["level"] for row in everything["levels"]] == [1, 2], "the demo stays out"
    assert everything["options"] == {"levels": [1, 2], "versions": ["0.9.0", "1.0.0"], "modes": ["demo", "normal"]}
    assert everything["source_labels"]["spikes"] == "picos"
    assert len(everything["heatmaps"]) == 4
    assert everything["chart"][1]["planned"] == 1.0

    ana = client.get("/api/analytics", params={"player": "ana"}).json()
    assert ana["files"] == 3
    level_two = client.get("/api/analytics", params={"level": 2}).json()
    assert [row["attempts"] for row in level_two["levels"]] == [2]
    version = client.get("/api/analytics", params={"version": "1.0.0"}).json()
    assert version["files"] == 1 and version["levels"][0]["completed"] == 1
    demo = client.get("/api/analytics", params={"mode": "demo"}).json()
    assert [row["deaths"] for row in demo["levels"]] == [1], "asked for, the demo counts"
    assert client.get("/api/analytics", params={"mode": "nope"}).status_code == 422
