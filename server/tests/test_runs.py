from fastapi.testclient import TestClient

RUN_ID = "a1b2c3d4e5f60718"


def _event(seq: int, kind: str = "enemy_killed", level: int = 1, **payload) -> dict:
    return {"seq": seq, "type": kind, "level": level, "t_run_s": seq * 1.5, "payload": payload}


def test_run_lifecycle(client: TestClient, start_run, finish_run) -> None:
    created = start_run(RUN_ID, start_level=1)
    assert created["outcome"] == "in_progress"
    assert created["player_name"] == "Ana"
    assert created["ended_at"] is None

    finished = finish_run(RUN_ID, score=250, level=3)

    assert finished["outcome"] == "died"
    assert finished["score"] == 250
    assert finished["level_reached"] == 3
    assert finished["ended_at"] is not None
    assert client.get(f"/api/runs/{RUN_ID}").json()["duration_s"] == 42.5


def test_creating_the_same_run_twice_is_idempotent(client: TestClient, start_run) -> None:
    start_run(RUN_ID)

    again = client.post("/api/runs", json={"id": RUN_ID, "player_name": "Ana"})

    assert again.status_code == 200
    assert len(client.get("/api/runs").json()) == 1


def test_creates_a_run_for_an_existing_player_id(client: TestClient) -> None:
    player = client.post("/api/players", json={"name": "Bruno"}).json()

    response = client.post("/api/runs", json={"player_id": player["id"], "mode": "test"})

    assert response.status_code == 201
    assert response.json()["player_name"] == "Bruno"
    assert len(response.json()["id"]) == 32


def test_event_batch_is_stored_in_order(client: TestClient, start_run) -> None:
    start_run(RUN_ID)
    batch = [
        _event(0, "level_started", lives=3),
        _event(1, "enemy_killed", enemy="Skeleton"),
        _event(2, "key_picked"),
        _event(3, "coin_picked", amount=5),
    ]

    response = client.post(f"/api/runs/{RUN_ID}/events", json={"events": batch})

    assert response.status_code == 201
    assert response.json() == {"received": 4, "inserted": 4}
    events = client.get(f"/api/runs/{RUN_ID}").json()["events"]
    assert [e["type"] for e in events] == ["level_started", "enemy_killed", "key_picked", "coin_picked"]
    assert events[1]["payload"] == {"enemy": "Skeleton"}


def test_resent_events_are_not_duplicated(client: TestClient, start_run) -> None:
    start_run(RUN_ID)
    client.post(f"/api/runs/{RUN_ID}/events", json={"events": [_event(0), _event(1)]})

    response = client.post(f"/api/runs/{RUN_ID}/events", json={"events": [_event(1), _event(2)]})

    assert response.json() == {"received": 2, "inserted": 1}
    assert len(client.get(f"/api/runs/{RUN_ID}").json()["events"]) == 3


def test_events_update_the_level_reached_of_a_run_in_progress(client: TestClient, start_run) -> None:
    start_run(RUN_ID)

    client.post(f"/api/runs/{RUN_ID}/events", json={"events": [_event(0, "level_started", level=4)]})

    assert client.get(f"/api/runs/{RUN_ID}").json()["level_reached"] == 4


def test_lists_runs_filtered_by_player_and_mode(client: TestClient, start_run) -> None:
    start_run("run-ana-normal", player="Ana")
    start_run("run-ana-test", player="Ana", mode="test")
    start_run("run-bruno-normal", player="Bruno")

    by_player = client.get("/api/runs", params={"player": "ana"}).json()
    by_both = client.get("/api/runs", params={"player": "Ana", "mode": "test"}).json()

    assert {r["id"] for r in by_player} == {"run-ana-normal", "run-ana-test"}
    assert [r["id"] for r in by_both] == ["run-ana-test"]
    assert len(client.get("/api/runs", params={"limit": 1}).json()) == 1


def test_unknown_run_returns_404(client: TestClient) -> None:
    finish = {"outcome": "quit", "score": 0, "level_reached": 1, "enemies_killed": 0, "duration_s": 1}

    assert client.get("/api/runs/does-not-exist").status_code == 404
    assert client.patch("/api/runs/does-not-exist", json=finish).status_code == 404
    events = client.post("/api/runs/does-not-exist/events", json={"events": [_event(0)]})
    assert events.status_code == 404


def test_unknown_player_id_returns_404(client: TestClient) -> None:
    assert client.post("/api/runs", json={"player_id": 999}).status_code == 404


def test_validation_errors_return_422(client: TestClient, start_run) -> None:
    start_run(RUN_ID)
    bad_requests = [
        ("post", "/api/runs", {"mode": "normal"}),  # no player
        ("post", "/api/runs", {"player_name": "Ana", "player_id": 1}),  # both
        ("post", "/api/runs", {"player_name": "Ana", "mode": "hard"}),
        ("post", "/api/runs", {"player_name": "Ana", "id": "bad id!"}),
        ("patch", f"/api/runs/{RUN_ID}", {"outcome": "in_progress", "score": 0,
                                           "level_reached": 1, "enemies_killed": 0, "duration_s": 0}),
        ("patch", f"/api/runs/{RUN_ID}", {"outcome": "died", "score": -1,
                                           "level_reached": 1, "enemies_killed": 0, "duration_s": 0}),
        ("post", f"/api/runs/{RUN_ID}/events", {"events": []}),
        ("post", f"/api/runs/{RUN_ID}/events", {"events": [{"seq": 0, "type": "Bad Type"}]}),
        ("post", f"/api/runs/{RUN_ID}/events", {"events": [{"seq": -1, "type": "ok"}]}),
    ]
    for method, url, body in bad_requests:
        response = client.request(method, url, json=body)
        assert response.status_code == 422, (method, url, body, response.text)
