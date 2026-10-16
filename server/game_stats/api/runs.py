from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status

from ..models import (
    EventBatch,
    EventBatchResult,
    Mode,
    PlayerNotFound,
    Run,
    RunCreate,
    RunDetail,
    RunFinish,
    RunNotFound,
)
from .dependencies import Repository

router = APIRouter(prefix="/api/runs", tags=["runs"])


def _not_found(error: Exception) -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(error))


@router.post("", response_model=Run, status_code=status.HTTP_201_CREATED)
def create_run(body: RunCreate, repo: Repository, response: Response) -> Run:
    """Start a run. Repeating it with the same id returns the stored run (200)."""
    try:
        run, created = repo.create_run(body)
    except PlayerNotFound as error:
        raise _not_found(error) from error
    if not created:
        response.status_code = status.HTTP_200_OK
    return run


@router.get("", response_model=list[Run])
def list_runs(
    repo: Repository,
    player: Annotated[str | None, Query(max_length=32)] = None,
    mode: Mode | None = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 50,
) -> list[Run]:
    return repo.list_runs(player=player, mode=mode, limit=limit)


@router.get("/{run_id}", response_model=RunDetail)
def get_run(run_id: str, repo: Repository) -> RunDetail:
    try:
        return repo.get_run_detail(run_id)
    except RunNotFound as error:
        raise _not_found(error) from error


@router.patch("/{run_id}", response_model=Run)
def finish_run(run_id: str, body: RunFinish, repo: Repository) -> Run:
    try:
        return repo.finish_run(run_id, body)
    except RunNotFound as error:
        raise _not_found(error) from error


@router.post("/{run_id}/events", response_model=EventBatchResult, status_code=status.HTTP_201_CREATED)
def add_events(run_id: str, body: EventBatch, repo: Repository) -> EventBatchResult:
    """Store a batch of events. Events with an already stored seq are ignored,
    so the game can resend a batch whose response it never received."""
    try:
        inserted = repo.add_events(run_id, body.events)
    except RunNotFound as error:
        raise _not_found(error) from error
    return EventBatchResult(received=len(body.events), inserted=inserted)
