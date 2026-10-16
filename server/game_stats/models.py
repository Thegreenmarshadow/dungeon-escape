"""Domain models: request payloads, responses and domain errors."""

from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Mode = Literal["normal", "test"]
Outcome = Literal["died", "quit", "in_progress"]
FinishedOutcome = Literal["died", "quit"]

RUN_ID_PATTERN = r"^[A-Za-z0-9_-]{8,64}$"
# Lowercase snake_case, so any future event type (e.g. "coin_picked") is valid.
EVENT_TYPE_PATTERN = r"^[a-z][a-z0-9_]{0,47}$"
MAX_EVENTS_PER_BATCH = 500
MAX_INT = 2**63 - 1


class RunNotFound(Exception):
    def __init__(self, run_id: str) -> None:
        super().__init__(f"run {run_id!r} not found")
        self.run_id = run_id


class PlayerNotFound(Exception):
    def __init__(self, player_id: int) -> None:
        super().__init__(f"player {player_id} not found")
        self.player_id = player_id


def to_utc_iso(value: datetime | None = None) -> str:
    """ISO 8601 UTC string with a trailing Z. Naive datetimes are taken as UTC."""
    value = value or datetime.now(UTC)
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


class _Input(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")


# --- Players -----------------------------------------------------------------


class PlayerIn(_Input):
    name: str = Field(min_length=1, max_length=32)


class Player(BaseModel):
    id: int
    name: str
    created_at: str


# --- Runs --------------------------------------------------------------------


class RunCreate(_Input):
    """A new run. The game sends its own id; the server generates one if missing.

    The player is given either by id or by name (get-or-create), so a run can
    be created in a single request when the game flushes its offline queue.
    """

    id: str | None = Field(default=None, pattern=RUN_ID_PATTERN)
    player_id: int | None = Field(default=None, ge=1)
    player_name: str | None = Field(default=None, min_length=1, max_length=32)
    mode: Mode = "normal"
    run_seed: int = Field(default=0, ge=0, le=MAX_INT)
    start_level: int = Field(default=1, ge=1, le=9999)
    started_at: datetime | None = None

    @model_validator(mode="after")
    def _needs_a_player(self) -> "RunCreate":
        if (self.player_id is None) == (self.player_name is None):
            raise ValueError("give exactly one of player_id or player_name")
        return self


class RunFinish(_Input):
    outcome: FinishedOutcome
    score: int = Field(ge=0, le=MAX_INT)
    level_reached: int = Field(ge=1, le=9999)
    enemies_killed: int = Field(ge=0, le=MAX_INT)
    duration_s: float = Field(ge=0)
    ended_at: datetime | None = None


class Run(BaseModel):
    id: str
    player_id: int
    player_name: str
    mode: Mode
    run_seed: int
    start_level: int
    started_at: str
    ended_at: str | None
    level_reached: int
    score: int
    enemies_killed: int
    outcome: Outcome
    duration_s: float


# --- Events ------------------------------------------------------------------


class EventIn(_Input):
    seq: int = Field(ge=0, le=MAX_INT)
    type: str = Field(pattern=EVENT_TYPE_PATTERN)
    level: int | None = Field(default=None, ge=1, le=9999)
    t_run_s: float = Field(default=0.0, ge=0)
    payload: dict[str, Any] = Field(default_factory=dict)
    # When the event happened on the client; defaults to the insertion time.
    at: datetime | None = None


class EventBatch(_Input):
    events: list[EventIn] = Field(min_length=1, max_length=MAX_EVENTS_PER_BATCH)


class EventBatchResult(BaseModel):
    received: int
    inserted: int


class Event(BaseModel):
    id: int
    seq: int
    type: str
    level: int | None
    t_run_s: float
    payload: dict[str, Any]
    created_at: str


class RunDetail(Run):
    events: list[Event]


# --- Leaderboard and stats ---------------------------------------------------


class LeaderboardEntry(BaseModel):
    rank: int
    run_id: str
    player_name: str
    score: int
    level_reached: int
    enemies_killed: int
    duration_s: float
    ended_at: str | None


class Leaderboard(BaseModel):
    entries: list[LeaderboardEntry]
    best_level: int


class Stats(BaseModel):
    total_players: int
    total_runs: int
    finished_runs: int
    total_kills: int
    keys_collected: int
    hearts_collected: int
    damage_taken: int
    levels_completed: int
    avg_duration_s: float
    best_level: int
    best_score: int
    events_by_type: dict[str, int]
