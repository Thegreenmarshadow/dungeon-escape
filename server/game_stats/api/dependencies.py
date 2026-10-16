"""Shared FastAPI dependencies."""

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request

from .. import database
from ..repository import SqliteStatsRepository


def get_repository(request: Request) -> Iterator[SqliteStatsRepository]:
    """One SQLite connection per request, closed when the request ends."""
    conn = database.connect(request.app.state.db_path)
    try:
        yield SqliteStatsRepository(conn)
    finally:
        conn.close()


Repository = Annotated[SqliteStatsRepository, Depends(get_repository)]
