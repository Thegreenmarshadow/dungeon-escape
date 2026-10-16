from fastapi import APIRouter, Response, status

from ..models import Player, PlayerIn
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
