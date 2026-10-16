"""Optional sample data: `uv run game-stats-seed [--db PATH] [--remove]`.

Every sample run id starts with "seed-", so the sample can be removed later
without touching real runs.
"""

import argparse
import random
from datetime import UTC, datetime, timedelta
from pathlib import Path

from . import database
from .models import EventIn, RunCreate, RunFinish
from .repository import SqliteStatsRepository

SEED_PREFIX = "seed-"
SAMPLE_PLAYERS = ["Ana", "Bruno", "Carla"]
RUNS_PER_PLAYER = 4
ENEMY_KINDS = ["Skeleton", "Vampire", "Skull", "Reaper"]


def _sample_run(repo: SqliteStatsRepository, rng: random.Random, player: str, index: int) -> None:
    run_id = f"{SEED_PREFIX}{player.lower()}-{index:02d}"
    mode = "test" if index == RUNS_PER_PLAYER - 1 else "normal"
    started = datetime.now(UTC) - timedelta(days=rng.randint(0, 20), minutes=rng.randint(0, 600))
    repo.create_run(
        RunCreate(id=run_id, player_name=player, mode=mode, run_seed=rng.randrange(2**32), started_at=started)
    )
    events: list[EventIn] = []
    t, kills, score, level = 0.0, 0, 0, 1
    levels = rng.randint(1, 4)

    def add(kind: str, payload: dict | None = None) -> None:
        events.append(EventIn(seq=len(events), type=kind, level=level, t_run_s=round(t, 1), payload=payload or {}))

    for level in range(1, levels + 1):
        add("level_started", {"lives": 3, "enemies_total": 6 + level * 2})
        level_start = t
        for _ in range(rng.randint(2, 6)):
            t += rng.uniform(4, 15)
            kills += 1
            score += 10
            add("enemy_killed", {"enemy": rng.choice(ENEMY_KINDS)})
            if rng.random() < 0.3:
                add("damage_taken", {"amount": 1, "lives": 2})
            if rng.random() < 0.2:
                add("heart_picked", {"amount": 1, "lives": 3})
        t += rng.uniform(5, 20)
        add("key_picked")
        if level < levels:
            t += rng.uniform(5, 20)
            score += 100
            add("level_completed", {"duration_s": round(t - level_start, 1), "score": score})
    add("player_died", {"score": score})
    repo.add_events(run_id, events)
    repo.finish_run(
        run_id,
        RunFinish(
            outcome="died",
            score=score,
            level_reached=levels,
            enemies_killed=kills,
            duration_s=round(t, 1),
            ended_at=started + timedelta(seconds=t),
        ),
    )


def seed(db_path: Path) -> int:
    database.initialize(db_path)
    conn = database.connect(db_path)
    try:
        repo = SqliteStatsRepository(conn)
        rng = random.Random(42)
        count = 0
        for player in SAMPLE_PLAYERS:
            for index in range(RUNS_PER_PLAYER):
                _sample_run(repo, rng, player, index)
                count += 1
        return count
    finally:
        conn.close()


def remove(db_path: Path) -> int:
    """Delete the sample runs (and their events) and sample players left without runs."""
    database.initialize(db_path)
    conn = database.connect(db_path)
    try:
        with conn:
            deleted = conn.execute("DELETE FROM runs WHERE id LIKE ?", (f"{SEED_PREFIX}%",)).rowcount
            placeholders = ",".join("?" * len(SAMPLE_PLAYERS))
            conn.execute(
                f"DELETE FROM players WHERE name IN ({placeholders}) "
                "AND id NOT IN (SELECT player_id FROM runs)",
                SAMPLE_PLAYERS,
            )
        return deleted
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Insert or remove sample stats data")
    parser.add_argument("--db", type=Path, default=None, help="SQLite file (default: server/data/game.db)")
    parser.add_argument("--remove", action="store_true", help="delete the sample data instead")
    args = parser.parse_args()
    db_path = args.db or database.configured_db_path()
    if args.remove:
        print(f"Removed {remove(db_path)} sample runs from {db_path}")
    else:
        print(f"Inserted {seed(db_path)} sample runs into {db_path}")


if __name__ == "__main__":
    main()
