from typing import Annotated

from fastapi import APIRouter, Query

from ..models import Leaderboard
from .dependencies import Repository

router = APIRouter(prefix="/api/leaderboard", tags=["leaderboard"])


@router.get("", response_model=Leaderboard)
def get_leaderboard(
    repo: Repository,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    player: Annotated[str | None, Query(max_length=32)] = None,
) -> Leaderboard:
    """Best finished runs in normal mode, highest score first (of one player if given)."""
    return repo.leaderboard(limit, player)
