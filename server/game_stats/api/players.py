from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status

from ..models import Mode, Player, PlayerIn, PlayerNotFound, PlayerProfile, PlayerTotals
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


# Declared after /totals so that path is not taken for a player id.
@router.get("/{player_id}", response_model=PlayerProfile, responses={404: {"description": "unknown player"}})
def player_profile(
    player_id: int,
    repo: Repository,
    limit: Annotated[int, Query(ge=1, le=1000)] = 500,
) -> PlayerProfile:
    """One player's profile: totals over every run and per mode, best run and
    the latest runs (at most limit), newest first."""
    try:
        return repo.player_profile(player_id, limit)
    except PlayerNotFound as error:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(error)) from error
