import json
from typing import Annotated, Any

from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from fastapi.concurrency import run_in_threadpool
from pydantic import ValidationError

from ..models import (
    EventBatch,
    EventBatchResult,
    LevelTrackIn,
    LevelTrackResult,
    LevelTrackView,
    MAX_LEVEL_BYTES,
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


@router.post(
    "/{run_id}/levels",
    response_model=LevelTrackResult,
    status_code=status.HTTP_201_CREATED,
    responses={404: {"description": "unknown run"}, 413: {"description": "file too large"}},
)
async def add_level_track(run_id: str, request: Request, repo: Repository, response: Response) -> LevelTrackResult:
    """Store one level telemetry file (the JSON the game's Telemetry writes),
    sent as is in the body. run_id is the server's run, which must exist first.
    Sending the same run, level and attempt again changes nothing (200)."""
    raw = await _read_level_json(request)
    try:
        track = LevelTrackIn.model_validate(raw)
    except ValidationError as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=error.errors(include_url=False, include_context=False, include_input=False),
        ) from error
    try:
        created = await run_in_threadpool(repo.add_level_track, run_id, track, raw)
    except RunNotFound as error:
        raise _not_found(error) from error
    if not created:
        response.status_code = status.HTTP_200_OK
    return LevelTrackResult(run_id=run_id, level=track.level, attempt=track.attempt, created=created)


@router.get("/{run_id}/levels", response_model=list[LevelTrackView])
def list_level_tracks(run_id: str, repo: Repository) -> list[LevelTrackView]:
    """The run's levels with map, route, events and summary, to draw them."""
    try:
        return repo.list_level_tracks(run_id)
    except RunNotFound as error:
        raise _not_found(error) from error


async def _read_level_json(request: Request) -> dict[str, Any]:
    too_large = HTTPException(
        status_code=status.HTTP_413_CONTENT_TOO_LARGE,
        detail=f"a level file can have at most {MAX_LEVEL_BYTES} bytes",
    )
    declared = request.headers.get("content-length", "")
    if declared.isdigit() and int(declared) > MAX_LEVEL_BYTES:
        raise too_large
    body = bytearray()
    async for chunk in request.stream():
        body += chunk
        if len(body) > MAX_LEVEL_BYTES:
            raise too_large
    try:
        raw = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="the body is not JSON") from error
    if not isinstance(raw, dict):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="expected a JSON object")
    return raw
