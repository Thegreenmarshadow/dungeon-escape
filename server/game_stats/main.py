"""Command line entry point: `uv run game-stats`."""

import argparse
import os

import uvicorn

from . import database

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765


def run() -> None:
    parser = argparse.ArgumentParser(description="Dungeon Escape stats server")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--db", help=f"SQLite file (default: {database.DEFAULT_DB_PATH})")
    parser.add_argument("--reload", action="store_true", help="restart on code changes")
    args = parser.parse_args()
    if args.db:
        os.environ[database.DB_PATH_ENV] = os.path.abspath(args.db)
    uvicorn.run(
        "game_stats.app:create_app",
        factory=True,
        host=args.host,
        port=args.port,
        reload=args.reload,
    )


if __name__ == "__main__":
    run()
