from fastapi.testclient import TestClient


def test_creates_a_new_player(client: TestClient) -> None:
    response = client.post("/api/players", json={"name": "Ana"})

    assert response.status_code == 201
    assert response.json()["name"] == "Ana"


def test_returns_the_existing_player_for_the_same_name(client: TestClient) -> None:
    first = client.post("/api/players", json={"name": "Ana"}).json()

    again = client.post("/api/players", json={"name": "  ana "})

    assert again.status_code == 200
    assert again.json()["id"] == first["id"]
    assert [p["name"] for p in client.get("/api/players").json()] == ["Ana"]


def test_rejects_an_empty_name(client: TestClient) -> None:
    assert client.post("/api/players", json={"name": "   "}).status_code == 422


def test_rejects_a_name_that_is_too_long(client: TestClient) -> None:
    assert client.post("/api/players", json={"name": "x" * 33}).status_code == 422
