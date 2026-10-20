"""FastAPI application: JSON API under /api and the web UI at /."""

from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from . import database
from .api import analytics, leaderboard, players, runs, stats

WEB_DIR = database.SERVER_DIR / "web"


def create_app(db_path: Path | None = None) -> FastAPI:
    """Build the app and create the database if it does not exist yet."""
    db_path = db_path or database.configured_db_path()
    database.initialize(db_path)

    app = FastAPI(title="Dungeon Escape stats", version="0.1.0")
    app.state.db_path = db_path

    @app.get("/api/health", tags=["health"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(players.router)
    app.include_router(runs.router)
    app.include_router(leaderboard.router)
    app.include_router(stats.router)
    app.include_router(analytics.router)
    # Mounted last so the /api routes take precedence.
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return app
