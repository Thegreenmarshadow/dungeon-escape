"""SQLite adapter: the only module that knows about tables and SQL."""

import json
import sqlite3
import uuid
from typing import Any

from .models import (
    Event,
    EventIn,
    Leaderboard,
    LeaderboardEntry,
    Mode,
    Player,
    PlayerNotFound,
    Run,
    RunCreate,
    RunDetail,
    RunFinish,
    RunNotFound,
    Stats,
    to_utc_iso,
)

# Event types the game sends that the stats endpoint summarizes. Any other type
# is stored and counted in events_by_type as well.
KILL_EVENT = "enemy_killed"
KEY_EVENT = "key_picked"
HEART_EVENT = "heart_picked"
DAMAGE_EVENT = "damage_taken"
LEVEL_COMPLETED_EVENT = "level_completed"
COIN_EVENT = "coin_picked"  # payload {"amount": int}
ITEM_BOUGHT_EVENT = "item_bought"  # payload {"item": str, "price": int}
UNKNOWN_ITEM = "unknown"


def _payload_int(path: str) -> str:
    """SQL expression for a numeric field of e.payload, truncated to an integer.
    A missing, negative or non-numeric value (or a malformed payload) counts as 0."""
    return (
        "CASE WHEN json_valid(e.payload) THEN"
        f" CASE WHEN json_type(e.payload, '{path}') IN ('integer', 'real')"
        f" THEN MAX(CAST(json_extract(e.payload, '{path}') AS INTEGER), 0) ELSE 0 END"
        " ELSE 0 END"
    )


def _payload_text(path: str, default: str) -> str:
    """SQL expression for a text field of e.payload, or default if it is not text."""
    return (
        "CASE WHEN json_valid(e.payload) THEN"
        f" CASE WHEN json_type(e.payload, '{path}') = 'text'"
        f" THEN json_extract(e.payload, '{path}') ELSE '{default}' END"
        f" ELSE '{default}' END"
    )


# TOTAL() never overflows and is 0.0 (not NULL) without rows; the CAST turns it
# back into an integer.
_COIN_AMOUNT = _payload_int("$.amount")
_ITEM_PRICE = _payload_int("$.price")


def _run_sum(expression: str, event_type: str) -> str:
    """Correlated subquery: sum of expression over one event type of run r."""
    return (
        f"(SELECT CAST(TOTAL({expression}) AS INTEGER) FROM events e"
        f" WHERE e.run_id = r.id AND e.type = '{event_type}')"
    )


_RUN_COINS_COLLECTED = _run_sum(_COIN_AMOUNT, COIN_EVENT)
_RUN_COINS_SPENT = _run_sum(_ITEM_PRICE, ITEM_BOUGHT_EVENT)

_RUN_COLUMNS = f"""
    r.id, r.player_id, p.name AS player_name, r.mode, r.run_seed, r.start_level,
    r.started_at, r.ended_at, r.level_reached, r.score, r.enemies_killed,
    r.outcome, r.duration_s,
    {_RUN_COINS_COLLECTED} AS coins_collected, {_RUN_COINS_SPENT} AS coins_spent
"""


class SqliteStatsRepository:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self._conn = conn

    # --- Players -------------------------------------------------------------

    def get_or_create_player(self, name: str) -> tuple[Player, bool]:
        """Player with that name (case-insensitive); created if missing."""
        with self._conn:
            cursor = self._conn.execute(
                "INSERT OR IGNORE INTO players (name, created_at) VALUES (?, ?)",
                (name, to_utc_iso()),
            )
        created = cursor.rowcount == 1
        row = self._conn.execute(
            "SELECT id, name, created_at FROM players WHERE name = ?", (name,)
        ).fetchone()
        return Player(**dict(row)), created

    def list_players(self) -> list[Player]:
        rows = self._conn.execute(
            "SELECT id, name, created_at FROM players ORDER BY name"
        ).fetchall()
        return [Player(**dict(row)) for row in rows]

    def _require_player(self, player_id: int) -> None:
        row = self._conn.execute("SELECT 1 FROM players WHERE id = ?", (player_id,)).fetchone()
        if row is None:
            raise PlayerNotFound(player_id)

    # --- Runs ----------------------------------------------------------------

    def create_run(self, data: RunCreate) -> tuple[Run, bool]:
        """Create the run. An id that already exists returns the stored run
        unchanged, so the game can safely retry the request."""
        if data.player_name is not None:
            player_id = self.get_or_create_player(data.player_name)[0].id
        else:
            player_id = data.player_id
            self._require_player(player_id)
        run_id = data.id or uuid.uuid4().hex
        with self._conn:
            cursor = self._conn.execute(
                """
                INSERT OR IGNORE INTO runs
                    (id, player_id, mode, run_seed, start_level, started_at, level_reached)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    player_id,
                    data.mode,
                    data.run_seed,
                    data.start_level,
                    to_utc_iso(data.started_at),
                    data.start_level,
                ),
            )
        return self.get_run(run_id), cursor.rowcount == 1

    def get_run(self, run_id: str) -> Run:
        row = self._conn.execute(
            f"SELECT {_RUN_COLUMNS} FROM runs r JOIN players p ON p.id = r.player_id WHERE r.id = ?",
            (run_id,),
        ).fetchone()
        if row is None:
            raise RunNotFound(run_id)
        return Run(**dict(row))

    def get_run_detail(self, run_id: str) -> RunDetail:
        run = self.get_run(run_id)
        return RunDetail(**run.model_dump(), events=self.list_events(run_id))

    def list_runs(self, player: str | None = None, mode: Mode | None = None, limit: int = 50) -> list[Run]:
        """Most recent runs first, optionally filtered by player name and mode."""
        where, params = [], []
        if player:
            where.append("p.name = ?")
            params.append(player)
        if mode:
            where.append("r.mode = ?")
            params.append(mode)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        rows = self._conn.execute(
            f"""
            SELECT {_RUN_COLUMNS} FROM runs r JOIN players p ON p.id = r.player_id
            {clause} ORDER BY r.started_at DESC, r.rowid DESC LIMIT ?
            """,
            (*params, limit),
        ).fetchall()
        return [Run(**dict(row)) for row in rows]

    def finish_run(self, run_id: str, data: RunFinish) -> Run:
        """Store the final result. Repeating it overwrites with the same values."""
        with self._conn:
            cursor = self._conn.execute(
                """
                UPDATE runs SET outcome = ?, score = ?, level_reached = ?,
                    enemies_killed = ?, duration_s = ?, ended_at = ?
                WHERE id = ?
                """,
                (
                    data.outcome,
                    data.score,
                    data.level_reached,
                    data.enemies_killed,
                    data.duration_s,
                    to_utc_iso(data.ended_at),
                    run_id,
                ),
            )
        if cursor.rowcount == 0:
            raise RunNotFound(run_id)
        return self.get_run(run_id)

    # --- Events --------------------------------------------------------------

    def add_events(self, run_id: str, events: list[EventIn]) -> int:
        """Insert a batch; events whose seq is already stored are skipped.
        Returns how many were inserted."""
        self.get_run(run_id)
        rows = [
            (
                run_id,
                event.seq,
                event.type,
                event.level,
                event.t_run_s,
                json.dumps(event.payload, ensure_ascii=False),
                to_utc_iso(event.at),
            )
            for event in events
        ]
        with self._conn:
            before = self._conn.total_changes
            self._conn.executemany(
                """
                INSERT OR IGNORE INTO events (run_id, seq, type, level, t_run_s, payload, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
            inserted = self._conn.total_changes - before
            # A run in progress shows how far it got, even before it ends.
            levels = [event.level for event in events if event.level is not None]
            if levels:
                self._conn.execute(
                    "UPDATE runs SET level_reached = MAX(level_reached, ?) "
                    "WHERE id = ? AND outcome = 'in_progress'",
                    (max(levels), run_id),
                )
        return inserted

    def list_events(self, run_id: str) -> list[Event]:
        rows = self._conn.execute(
            """
            SELECT id, seq, type, level, t_run_s, payload, created_at
            FROM events WHERE run_id = ? ORDER BY seq
            """,
            (run_id,),
        ).fetchall()
        return [Event(**{**dict(row), "payload": _decode_payload(row["payload"])}) for row in rows]

    # --- Leaderboard and stats -----------------------------------------------

    def leaderboard(self, limit: int = 10) -> Leaderboard:
        """Best finished normal-mode runs: test runs and runs in progress are excluded."""
        finished_normal = "r.mode = 'normal' AND r.outcome != 'in_progress'"
        rows = self._conn.execute(
            f"""
            SELECT r.id AS run_id, p.name AS player_name, r.score, r.level_reached,
                   r.enemies_killed, {_RUN_COINS_COLLECTED} AS coins_collected,
                   r.duration_s, r.ended_at
            FROM runs r JOIN players p ON p.id = r.player_id
            WHERE {finished_normal}
            ORDER BY r.score DESC, r.level_reached DESC, r.duration_s ASC, r.ended_at ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        best_level = self._conn.execute(
            f"SELECT COALESCE(MAX(r.level_reached), 0) FROM runs r WHERE {finished_normal}"
        ).fetchone()[0]
        entries = [LeaderboardEntry(rank=i + 1, **dict(row)) for i, row in enumerate(rows)]
        return Leaderboard(entries=entries, best_level=best_level)

    def stats(self, mode: Mode | None = None) -> Stats:
        run_filter = "WHERE r.mode = ?" if mode else ""
        params: tuple[Any, ...] = (mode,) if mode else ()
        runs = self._conn.execute(
            f"""
            SELECT COUNT(*) AS total_runs,
                   COUNT(DISTINCT r.player_id) AS total_players,
                   SUM(r.outcome != 'in_progress') AS finished_runs,
                   AVG(CASE WHEN r.outcome != 'in_progress' THEN r.duration_s END) AS avg_duration_s,
                   MAX(r.level_reached) AS best_level,
                   MAX(r.score) AS best_score
            FROM runs r {run_filter}
            """,
            params,
        ).fetchone()
        by_type = dict(
            self._conn.execute(
                f"""
                SELECT e.type, COUNT(*) FROM events e JOIN runs r ON r.id = e.run_id
                {run_filter} GROUP BY e.type ORDER BY COUNT(*) DESC, e.type
                """,
                params,
            ).fetchall()
        )
        damage = self._conn.execute(
            f"""
            SELECT COALESCE(SUM(COALESCE(json_extract(e.payload, '$.amount'), 1)), 0)
            FROM events e JOIN runs r ON r.id = e.run_id
            WHERE e.type = ? {"AND r.mode = ?" if mode else ""}
            """,
            (DAMAGE_EVENT, *params),
        ).fetchone()[0]
        mode_filter = "AND r.mode = ?" if mode else ""
        coins = self._conn.execute(
            f"""
            SELECT CAST(TOTAL(CASE WHEN e.type = ? THEN {_COIN_AMOUNT} END) AS INTEGER) AS collected,
                   CAST(TOTAL(CASE WHEN e.type = ? THEN {_ITEM_PRICE} END) AS INTEGER) AS spent
            FROM events e JOIN runs r ON r.id = e.run_id
            WHERE e.type IN (?, ?) {mode_filter}
            """,
            (COIN_EVENT, ITEM_BOUGHT_EVENT, COIN_EVENT, ITEM_BOUGHT_EVENT, *params),
        ).fetchone()
        item = _payload_text("$.item", UNKNOWN_ITEM)
        by_item = dict(
            self._conn.execute(
                f"""
                SELECT {item} AS item, COUNT(*) FROM events e JOIN runs r ON r.id = e.run_id
                WHERE e.type = ? {mode_filter} GROUP BY item ORDER BY COUNT(*) DESC, item
                """,
                (ITEM_BOUGHT_EVENT, *params),
            ).fetchall()
        )
        return Stats(
            total_players=runs["total_players"],
            total_runs=runs["total_runs"],
            finished_runs=runs["finished_runs"] or 0,
            total_kills=by_type.get(KILL_EVENT, 0),
            keys_collected=by_type.get(KEY_EVENT, 0),
            hearts_collected=by_type.get(HEART_EVENT, 0),
            damage_taken=int(damage),
            coins_collected=coins["collected"],
            coins_spent=coins["spent"],
            items_bought=by_type.get(ITEM_BOUGHT_EVENT, 0),
            items_bought_by_item=by_item,
            levels_completed=by_type.get(LEVEL_COMPLETED_EVENT, 0),
            avg_duration_s=round(runs["avg_duration_s"] or 0.0, 1),
            best_level=runs["best_level"] or 0,
            best_score=runs["best_score"] or 0,
            events_by_type=by_type,
        )


def _decode_payload(raw: str) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}
