import json
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from game_stats.app import create_app


@pytest.fixture
def client(tmp_path: Path) -> Iterator[TestClient]:
    """API client backed by a fresh database in a temporary folder."""
    app = create_app(tmp_path / "test.db")
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def start_run(client: TestClient) -> Callable[..., dict[str, Any]]:
    def _start(run_id: str, player: str = "Ana", mode: str = "normal", **extra: Any) -> dict[str, Any]:
        body = {"id": run_id, "player_name": player, "mode": mode, "run_seed": 7, **extra}
        response = client.post("/api/runs", json=body)
        assert response.status_code == 201, response.text
        return response.json()

    return _start


@pytest.fixture
def finish_run(client: TestClient) -> Callable[..., dict[str, Any]]:
    def _finish(run_id: str, score: int, outcome: str = "died", level: int = 1) -> dict[str, Any]:
        body = {
            "outcome": outcome,
            "score": score,
            "level_reached": level,
            "enemies_killed": score // 10,
            "duration_s": 42.5,
        }
        response = client.patch(f"/api/runs/{run_id}", json=body)
        assert response.status_code == 200, response.text
        return response.json()

    return _finish


FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def level_file() -> Callable[..., dict[str, Any]]:
    """A copy of a sample level telemetry file (tests/fixtures), with overrides."""

    def _load(name: str, **overrides: Any) -> dict[str, Any]:
        data = json.loads((FIXTURES_DIR / f"{name}.json").read_text(encoding="utf-8"))
        return {**data, **overrides}

    return _load


@pytest.fixture
def upload_level(client: TestClient) -> Callable[..., Any]:
    def _upload(run_id: str, data: dict[str, Any], expected: int = 201) -> dict[str, Any]:
        response = client.post(f"/api/runs/{run_id}/levels", json=data)
        assert response.status_code == expected, response.text
        return response.json()

    return _upload
