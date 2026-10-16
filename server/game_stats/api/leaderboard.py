from typing import Annotated

from fastapi import APIRouter, Query

from ..models import Leaderboard
from .dependencies import Repository

router = APIRouter(prefix="/api/leaderboard", tags=["leaderboard"])


@router.get("", response_model=Leaderboard)
def get_leaderboard(repo: Repository, limit: Annotated[int, Query(ge=1, le=100)] = 10) -> Leaderboard:
    """Best finished runs in normal mode, highest score first."""
    return repo.leaderboard(limit)
