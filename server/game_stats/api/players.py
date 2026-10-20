from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from ..models import Mode, Player, PlayerIn, PlayerTotals
from .dependencies import Repository

router = APIRouter(prefix="/api/players", tags=["players"])


@router.post("", response_model=Player, status_code=status.HTTP_201_CREATED)
def get_or_create_player(body: PlayerIn, repo: Repository, response: Response) -> Player:
    """Return the player with that name, creating it if needed (201 vs 200)."""
    player, created = repo.get_or_create_player(body.name)
    if not created:
        response.status_code = status.HTTP_200_OK
    return player


@router.get("", response_model=list[Player])
def list_players(repo: Repository) -> list[Player]:
    return repo.list_players()


@router.get("/totals", response_model=list[PlayerTotals])
def player_totals(
    repo: Repository,
    mode: Mode | None = None,
    player: Annotated[str | None, Query(max_length=32)] = None,
) -> list[PlayerTotals]:
    """Per-player totals (score, play time, runs, best score, deepest level and
    deaths) over their runs of one mode, or all; the longest played first."""
    return repo.player_totals(mode, player)
