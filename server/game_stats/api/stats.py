from fastapi import APIRouter

from ..models import Mode, Stats
from .dependencies import Repository

router = APIRouter(tags=["stats"])


@router.get("/api/stats", response_model=Stats)
def get_stats(repo: Repository, mode: Mode | None = None) -> Stats:
    """Totals across all runs, or only the runs of one mode."""
    return repo.stats(mode)
