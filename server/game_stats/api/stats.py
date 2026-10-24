from typing import Annotated

from fastapi import APIRouter, Query

from ..models import Mode, Stats
from .dependencies import Repository

router = APIRouter(tags=["stats"])


@router.get("/api/stats", response_model=Stats)
def get_stats(
    repo: Repository,
    mode: Mode | None = None,
    player: Annotated[str | None, Query(max_length=32)] = None,
) -> Stats:
    """Totals across all runs, or only the runs of one mode and/or player."""
    return repo.stats(mode, player)
