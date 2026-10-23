"""Domain models: request payloads, responses and domain errors."""

from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Mode = Literal["normal", "test", "demo"]
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
    # Computed from the run's coin_picked and item_bought events.
    coins_collected: int = 0
    coins_spent: int = 0
    # Level telemetry files stored for the run (routes the page can draw).
    level_tracks: int = 0


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
    coins_collected: int
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
    coins_collected: int
    coins_spent: int
    items_bought: int
    items_bought_by_item: dict[str, int]
    levels_completed: int
    avg_duration_s: float
    best_level: int
    best_score: int
    events_by_type: dict[str, int]


class PlayerTotals(BaseModel):
    """Totals of one player over the runs that match the filters."""

    player_id: int
    player_name: str
    runs: int
    total_score: int
    total_time_s: float
    best_score: int
    deepest_level: int
    deaths: int
    last_played_at: str | None


class PlayerProfile(BaseModel):
    """One player's page: totals over every run and per mode, the best run
    (the one the leaderboard would rank: finished, normal mode) and the runs,
    newest first."""

    player: Player
    totals: PlayerTotals
    totals_by_mode: dict[str, PlayerTotals]
    first_played_at: str | None
    best_run: Run | None
    runs: list[Run]


# --- Level telemetry -----------------------------------------------------------
# The game's Telemetry autoload writes one JSON file per level played and
# uploads it as is (see docs/analitica.md for the format). Only the fields the
# server reads are validated; unknown fields are kept in the stored JSON.

LevelOutcome = Literal["completed", "died", "abandoned"]
# Upload size limit. A level file is a few KB (about 25 bytes per path sample).
MAX_LEVEL_BYTES = 2_000_000
MAX_MAP_SIDE = 512
MAX_PATH_SAMPLES = 100_000
MAX_LEVEL_EVENTS = 20_000
Cell = Annotated[list[int], Field(min_length=2, max_length=2)]


class LevelMapIn(BaseModel):
    model_config = ConfigDict(extra="allow")

    size: Annotated[list[Annotated[int, Field(ge=0, le=MAX_MAP_SIDE)]], Field(min_length=2, max_length=2)]
    cell_px: int = Field(default=16, ge=1, le=1024)
    origin: Annotated[list[float], Field(min_length=2, max_length=2)] = [0.0, 0.0]
    floor_encoding: Literal["rle"] = "rle"
    floor: str = Field(default="", max_length=MAX_MAP_SIDE * MAX_MAP_SIDE, pattern=r"^[0-9,]*$")
    door: Cell | None = None
    key: Cell | None = None
    start: Cell | None = None
    rooms: Annotated[list[Annotated[list[int], Field(min_length=4)]], Field(max_length=1000)] = []


class LevelEventIn(BaseModel):
    model_config = ConfigDict(extra="allow")

    t: float = Field(ge=0)
    type: str = Field(pattern=EVENT_TYPE_PATTERN)
    x: float = 0.0
    y: float = 0.0


class LevelTrackIn(BaseModel):
    """Shape check of an uploaded level file."""

    model_config = ConfigDict(extra="allow")

    schema_version: int = Field(ge=1, le=1000)
    game_version: str = Field(default="", max_length=32)
    run_id: str = Field(default="", max_length=64)
    profile: str = Field(default="", max_length=64)
    mode: Mode = "normal"
    level: int = Field(ge=1, le=9999)
    attempt: int = Field(default=1, ge=1, le=9999)
    outcome: LevelOutcome
    duration_s: float = Field(default=0.0, ge=0, le=7 * 24 * 3600)
    level_seed: Annotated[str, Field(max_length=32)] | int | None = None
    map: LevelMapIn
    path: Annotated[
        list[Annotated[list[float], Field(min_length=3)]], Field(max_length=MAX_PATH_SAMPLES)
    ] = []
    events: Annotated[list[LevelEventIn], Field(max_length=MAX_LEVEL_EVENTS)] = []
    weapons_used: Annotated[list[Annotated[str, Field(max_length=64)]], Field(max_length=200)] = []
    # Planned difficulty (DifficultyCurve.index_for); null for hand-made levels
    # and for files written before the field existed.
    difficulty_index: float | None = None


class LevelTrackResult(BaseModel):
    run_id: str
    level: int
    attempt: int
    created: bool


class LevelTrackInfo(BaseModel):
    """A stored level without its route: one row of a run's level list."""

    run_id: str
    level: int
    attempt: int
    mode: Mode
    game_version: str
    outcome: LevelOutcome
    duration_s: float
    difficulty_index: float | None
    received_at: str


class LevelTrackView(LevelTrackInfo):
    """Everything the route view draws: the map already decoded (cells: one
    digit per cell, 0 empty, 1 floor, 2 wall), the route, the events and a
    summary (damage by source, death causes, kills...)."""

    label: str
    map: dict[str, Any]
    path: list[list[float]]
    events: list[dict[str, Any]]
    weapons_used: list[str]
    summary: dict[str, Any]
