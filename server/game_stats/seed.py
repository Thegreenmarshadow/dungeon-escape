"""Optional sample data: `uv run game-stats-seed [--db PATH] [--remove]`.

Fills the database with sample players, runs, run events and level telemetry
files (map, route and events), so every section of the web page has data.
Routes are walked on real level maps: seed_maps.json holds the maps of the
level files in tests/fixtures, and the deeper levels reuse them mirrored.

The data follows the game's rules (Game.STARTING_HEALTH, POINTS_PER_KILL,
POINTS_PER_LEVEL, the shop prices) and the formats of RunRecorder (events)
and Telemetry (level files), so the run events and the level files of a run
tell the same story. Both formats report the player's health and damage in
hearts ("lives", "amount"), although the game counts them in half hearts; the
sample stays on levels 1 to 6, where every hit takes a whole heart (the
damage bonus starts at level 25), so it only uses whole hearts. It is deterministic: the same database comes out every
time, except for the dates, which are relative to now.

Every sample run id starts with "seed-", so the sample can be removed later
without touching real runs.
"""

import argparse
import json
import math
import random
from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from . import database, level_maps
from .models import EventIn, LevelTrackIn, RunCreate, RunFinish
from .repository import SqliteStatsRepository

SEED_PREFIX = "seed-"
# Player name -> (runs, skill). Skill scales the chance of getting hurt and of
# dying: below 1 plays better than average.
SAMPLE_PLAYERS = {
    "Ana": (14, 0.75),
    "Bruno": (9, 1.0),
    "Carla": (6, 1.25),
    "Diego": (12, 0.9),
    "Elena": (4, 1.4),
    "Facu": (8, 1.1),
}
# This player's newest run is left in progress.
PLAYER_IN_PROGRESS = "Diego"
HISTORY_DAYS = 30
# Runs older than this were played with the previous game version.
NEW_VERSION_DAYS = 12
OLD_VERSION, NEW_VERSION = "0.9.0", "1.0.0"

# Game rules (scripts/game.gd and scripts/shop.gd), in hearts: the game's
# STARTING_HEALTH and DEMO_HEALTH are these times Heart.HALF_HEARTS_PER_HEART.
STARTING_LIVES = 3
DEMO_LIVES = 5
MAX_LIVES = 5
POINTS_PER_KILL = 10
POINTS_PER_LEVEL = 100
DAMAGE_BASE_PRICE = 10
DAMAGE_PRICE_STEP = 10
MAX_DAMAGE_BONUS = 3
LIFE_PRICE = 6
WEAPON_PRICE = 12
SHOP_WEAPONS = ("spear", "dagger")
START_WEAPON = "sword"
PICKUP_WEAPONS = ("axe", "katana", "mace", "crossbow", "frost_blade", "whip")

# Telemetry: walking speed seen in the sample files and the sampling period
# while standing still.
WALK_PX_S = 84.0
STILL_SAMPLE_S = 0.25
JITTER_PX = 2.5

MAX_LEVEL = 6
QUIT_CHANCE = 0.04
# Per level: base chance of dying in it, spike traps per walked cell, enemy
# fights per walked cell, chance a fight hurts, and who lives there. Level 3
# is the spike level, so the analytics have a clear warning to show.
LEVELS: dict[int, dict[str, Any]] = {
    1: {"die": 0.10, "spikes": 0.008, "fights": 0.05, "hurt": 0.15, "enemies": ("Skeleton",)},
    2: {"die": 0.20, "spikes": 0.006, "fights": 0.06, "hurt": 0.2, "enemies": ("Skeleton", "Vampire")},
    3: {"die": 0.50, "spikes": 0.03, "fights": 0.06, "hurt": 0.2, "enemies": ("Skeleton", "Skull")},
    4: {"die": 0.35, "spikes": 0.01, "fights": 0.08, "hurt": 0.3, "enemies": ("Archer", "Skull", "Vampire")},
    5: {"die": 0.45, "spikes": 0.01, "fights": 0.09, "hurt": 0.35, "enemies": ("Mage", "Mimic", "Vampire")},
    6: {"die": 0.65, "spikes": 0.012, "fights": 0.1, "hurt": 0.4, "enemies": ("Archer", "Mage", "SkullTurret", "Reaper")},
}
SPIKE_DEATH_SHARE = {3: 0.7}
DEFAULT_SPIKE_DEATH_SHARE = 0.25
# Planned difficulty (DifficultyCurve.index_for_level, rounded to 3 decimals);
# level 1 is hand-made. tests/test_difficulty_curve.gd in the game checks the
# same values.
PLANNED_INDEX = {2: 20.629, 3: 35.76, 4: 44.685, 5: 56.756, 6: 81.035}
# Maps of each level: (name in seed_maps.json, mirrored, level seed, weight).
LEVEL_MAPS: dict[int, list[tuple[str, bool, str | None, int]]] = {
    1: [("level_1", False, None, 1)],
    2: [("cavern_a", False, "7420309529871677574", 3), ("cavern_b", False, "5875422076221816051", 1)],
    3: [("cavern_b", True, "1846203391758221047", 1)],
    4: [("cavern_a", True, "9034471265501873310", 1)],
    5: [("cavern_b", False, "3328705149120488862", 1)],
    6: [("cavern_a", False, "6612094488031257719", 1)],
}
DEMO_MAP = "demo"
MAPS_FILE = Path(__file__).with_name("seed_maps.json")

Cell = tuple[int, int]


# --- Maps -----------------------------------------------------------------------


@dataclass
class SampleMap:
    """A level map: what the level file stores plus its decoded floor."""

    data: dict[str, Any]
    width: int
    height: int
    floor: bytearray

    @classmethod
    def from_data(cls, data: dict[str, Any]) -> "SampleMap":
        width, height = level_maps.map_size(data)
        return cls(data, width, height, level_maps.decode_floor(data))

    def is_floor(self, cell: Cell) -> bool:
        x, y = cell
        return 0 <= x < self.width and 0 <= y < self.height and self.floor[y * self.width + x] == 1

    def cell(self, key: str) -> Cell:
        found = level_maps.map_cell(self.data, key)
        if found is None:
            raise ValueError(f"sample map without {key}")
        return found

    def floor_cells(self) -> list[Cell]:
        return [(i % self.width, i // self.width) for i, value in enumerate(self.floor) if value]

    def route(self, start: Cell, goal: Cell) -> list[Cell]:
        """Shortest walk over floor cells, start excluded; [] if unreachable.
        Diagonal steps only where both side cells are floor (no wall corners)."""
        previous: dict[Cell, Cell | None] = {start: None}
        queue = deque([start])
        while queue:
            current = queue.popleft()
            if current == goal:
                break
            x, y = current
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                nxt = (x + dx, y + dy)
                if nxt in previous or not self.is_floor(nxt):
                    continue
                if dx and dy and not (self.is_floor((x + dx, y)) and self.is_floor((x, y + dy))):
                    continue
                previous[nxt] = current
                queue.append(nxt)
        if goal not in previous:
            return []
        steps: list[Cell] = []
        cell: Cell | None = goal
        while cell is not None and cell != start:
            steps.append(cell)
            cell = previous[cell]
        return steps[::-1]


def encode_floor(floor: bytearray) -> str:
    """Inverse of level_maps.decode_floor: run lengths, non-floor first."""
    runs, current, length = [], 0, 0
    for value in floor:
        if value == current:
            length += 1
        else:
            runs.append(length)
            current, length = value, 1
    runs.append(length)
    return ",".join(str(run) for run in runs)


def mirrored(data: dict[str, Any]) -> dict[str, Any]:
    """The map flipped left to right (a different level with the same rooms)."""
    width, height = level_maps.map_size(data)
    floor = level_maps.decode_floor(data)
    flipped = bytearray(len(floor))
    for y in range(height):
        row = y * width
        for x in range(width):
            flipped[row + width - 1 - x] = floor[row + x]
    out = {**data, "floor": encode_floor(flipped)}
    for key in ("door", "key", "start"):
        if data.get(key):
            out[key] = [width - 1 - data[key][0], data[key][1]]
    out["rooms"] = [[width - x - w, y, w, h, *rest] for x, y, w, h, *rest in data.get("rooms", [])]
    return out


def load_maps() -> dict[str, dict[str, Any]]:
    return json.loads(MAPS_FILE.read_text(encoding="utf-8"))


# --- One level ---------------------------------------------------------------------


@dataclass
class LevelPlay:
    """The level file of one level being played, plus the run events
    (RunRecorder) it causes, with times relative to the level start."""

    sample_map: SampleMap
    lives: int
    weapon: str
    path: list[list[float]] = field(default_factory=list)
    events: list[dict[str, Any]] = field(default_factory=list)
    run_events: list[tuple[float, str, dict[str, Any]]] = field(default_factory=list)
    weapons_used: list[str] = field(default_factory=list)
    kills: int = 0
    t: float = 0.0
    cell: Cell = (0, 0)
    x: float = 0.0
    y: float = 0.0

    def __post_init__(self) -> None:
        self.weapons_used.append(self.weapon)

    def place(self, rng: random.Random, cell: Cell) -> None:
        self.cell = cell
        self.x, self.y = _cell_center(self.sample_map, cell)
        self._sample(rng)

    def _sample(self, rng: random.Random) -> None:
        self.path.append([round(self.t, 2), round(self.x + rng.uniform(-JITTER_PX, JITTER_PX), 1),
                          round(self.y + rng.uniform(-JITTER_PX, JITTER_PX), 1)])

    def step(self, rng: random.Random, cell: Cell) -> None:
        """Walk to a neighbour cell: two samples, like the game's 8 px rule."""
        tx, ty = _cell_center(self.sample_map, cell)
        distance = math.hypot(tx - self.x, ty - self.y)
        seconds = distance / WALK_PX_S * rng.uniform(0.9, 1.25)
        sx, sy = self.x, self.y
        for k in (1, 2):
            self.t += seconds / 2
            self.x, self.y = sx + (tx - sx) * k / 2, sy + (ty - sy) * k / 2
            self._sample(rng)
        self.cell = cell

    def wait(self, rng: random.Random, seconds: float) -> None:
        end = self.t + seconds
        while self.t + STILL_SAMPLE_S <= end:
            self.t += STILL_SAMPLE_S
            self._sample(rng)
        self.t = end

    def event(self, kind: str, x: float | None = None, y: float | None = None, **fields: Any) -> None:
        self.events.append({"t": round(self.t, 2), "type": kind,
                            "x": round(self.x if x is None else x, 1),
                            "y": round(self.y if y is None else y, 1), **fields})

    def run_event(self, kind: str, **payload: Any) -> None:
        self.run_events.append((self.t, kind, payload))

    def hurt(self, source: str) -> None:
        self.lives -= 1
        self.event("damage", amount=1, source=source)
        self.run_event("damage_taken", amount=1, lives=self.lives, source=source)

    def heal(self) -> None:
        self.lives += 1
        self.event("heart", amount=1)
        self.run_event("heart_picked", amount=1, lives=self.lives)

    def change_weapon(self, weapon: str) -> None:
        self.weapon = weapon
        if weapon not in self.weapons_used:
            self.weapons_used.append(weapon)
        self.event("weapon_changed", weapon=weapon)
        self.run_event("weapon_changed", weapon=weapon)


def _cell_center(sample_map: SampleMap, cell: Cell) -> tuple[float, float]:
    size = level_maps.cell_px(sample_map.data)
    ox, oy = level_maps.origin(sample_map.data)
    return ox + (cell[0] + 0.5) * size, oy + (cell[1] + 0.5) * size


def _waypoints(rng: random.Random, sample_map: SampleMap) -> list[tuple[Cell, str]]:
    """Where the player goes: a detour or two, the key and the door. Sometimes
    the door first, to find it locked."""
    cells = sample_map.floor_cells()
    points = [(rng.choice(cells), "") for _ in range(rng.randint(1, 2))]
    if rng.random() < 0.2:
        points.append((sample_map.cell("door"), "locked"))
    points.append((sample_map.cell("key"), "key"))
    if rng.random() < 0.4:
        points.append((rng.choice(cells), ""))
    points.append((sample_map.cell("door"), "door"))
    return points


def play_level(
    rng: random.Random,
    sample_map: SampleMap,
    level: int,
    lives: int,
    weapon: str,
    skill: float,
    outcome: str,
    demo: bool = False,
) -> LevelPlay:
    """Walks one level to the given outcome ("completed", "died" or
    "abandoned"). A demo death revives the player at the start instead."""
    rules = LEVELS[min(level, MAX_LEVEL)]
    play = LevelPlay(sample_map, lives, weapon)
    start = sample_map.cell("start")
    play.place(rng, start)
    waypoints = _waypoints(rng, sample_map)
    # The walk ends early on the leg chosen for dying or quitting.
    stop_leg = rng.randrange(len(waypoints)) if outcome in ("died", "abandoned") else -1
    revive_leg = rng.randrange(len(waypoints)) if demo else -1
    has_key = False
    for leg, (target, purpose) in enumerate(waypoints):
        steps = sample_map.route(play.cell, target)
        if leg == stop_leg:
            steps = steps[: max(1, int(len(steps) * rng.uniform(0.3, 0.9)))]
        for cell in steps:
            play.step(rng, cell)
            _maybe_encounter(rng, play, rules, skill)
        if leg == stop_leg:
            break
        if leg == revive_leg:
            _demo_death_and_revive(rng, play, rules, start)
            continue
        if purpose == "key" and not has_key:
            has_key = True
            play.event("key")
            play.run_event("key_picked")
        elif purpose == "locked" and not has_key:
            play.event("door", state="locked")
            play.wait(rng, rng.uniform(0.5, 1.5))
        elif purpose == "door":
            play.event("door", state="escaped")
    if outcome == "died":
        _die(rng, play, rules, level)
    elif outcome == "abandoned":
        play.wait(rng, rng.uniform(1.0, 4.0))
    return play


def _maybe_encounter(rng: random.Random, play: LevelPlay, rules: dict[str, Any], skill: float) -> None:
    if rng.random() < rules["fights"]:
        _fight(rng, play, rules, skill)
    if rng.random() < rules["spikes"] and play.lives > 1 and rng.random() < min(1.0, skill):
        play.hurt("spikes")
    if play.lives < STARTING_LIVES and rng.random() < 0.01:
        play.heal()
    if rng.random() < 0.003:
        play.change_weapon(rng.choice(PICKUP_WEAPONS))


def _fight(rng: random.Random, play: LevelPlay, rules: dict[str, Any], skill: float) -> None:
    enemy = rng.choice(rules["enemies"])
    angle = rng.uniform(0, 2 * math.pi)
    reach = rng.uniform(12, 24)
    ex, ey = play.x + math.cos(angle) * reach, play.y + math.sin(angle) * reach
    for _ in range(rng.randint(1, 4)):
        play.wait(rng, rng.uniform(0.2, 0.6))
        play.event("attack", hit=rng.random() < 0.7)
    if play.lives > 1 and rng.random() < rules["hurt"] * skill:
        play.hurt(enemy)
    play.wait(rng, rng.uniform(0.2, 0.8))
    play.kills += 1
    play.event("enemy_killed", x=ex, y=ey, enemy=enemy)
    play.run_event("enemy_killed", enemy=enemy)
    if rng.random() < 0.6:
        play.run_event("coin_picked", amount=rng.randint(1, 4))


def _death_cause(rng: random.Random, rules: dict[str, Any], level: int) -> str:
    if rng.random() < SPIKE_DEATH_SHARE.get(level, DEFAULT_SPIKE_DEATH_SHARE):
        return "spikes"
    return rng.choice(rules["enemies"])


def _die(rng: random.Random, play: LevelPlay, rules: dict[str, Any], level: int) -> None:
    cause = _death_cause(rng, rules, level)
    play.wait(rng, rng.uniform(0.3, 1.5))
    while play.lives > 0:
        play.hurt(cause)
        if play.lives > 0:
            play.wait(rng, rng.uniform(0.4, 1.2))
    play.event("death", cause=cause, final=True)


def _demo_death_and_revive(rng: random.Random, play: LevelPlay, rules: dict[str, Any], start: Cell) -> None:
    """The demo kills the player on the spot and revives them at the start."""
    cause = rng.choice(rules["enemies"])
    play.lives = 0
    play.event("damage", amount=DEMO_LIVES, source=cause)
    play.run_event("damage_taken", amount=DEMO_LIVES, lives=0, source=cause)
    play.event("death", cause=cause, final=False)
    play.wait(rng, 1.0)
    play.lives = DEMO_LIVES
    sx, sy = _cell_center(play.sample_map, start)
    play.event("revive", x=sx, y=sy, lives=DEMO_LIVES, path_index=len(play.path))
    play.run_event("player_respawned", lives=DEMO_LIVES)
    play.place(rng, start)


# --- One run -------------------------------------------------------------------------


@dataclass
class RunPlan:
    run_id: str
    player: str
    mode: str
    skill: float
    started: datetime
    finished: bool = True


def _pick_map(rng: random.Random, maps: dict[str, dict[str, Any]], level: int) -> tuple[SampleMap, str | None]:
    options = LEVEL_MAPS[level]
    name, flip, level_seed, _ = rng.choices(options, weights=[o[3] for o in options])[0]
    data = mirrored(maps[name]) if flip else maps[name]
    return SampleMap.from_data(data), level_seed


def _level_outcome(rng: random.Random, plan: RunPlan, level: int) -> str:
    if plan.mode == "demo":
        return "completed" if rng.random() < 0.6 else "abandoned"
    roll = rng.random()
    die = min(LEVELS[level]["die"] * plan.skill, 0.9)
    if roll < die:
        return "died"
    if roll < die + QUIT_CHANCE:
        return "abandoned"
    return "completed"


def _level_file(plan: RunPlan, play: LevelPlay, level: int, level_seed: str | None,
                outcome: str, run_seed: int, started: datetime) -> dict[str, Any]:
    """The JSON the game's Telemetry writes for one level."""
    days_ago = (datetime.now(UTC) - plan.started).days
    return {
        "schema_version": 1,
        "game_version": NEW_VERSION if days_ago < NEW_VERSION_DAYS else OLD_VERSION,
        "profile": plan.player,
        "profile_slug": plan.player.lower(),
        "run_id": plan.run_id,
        "mode": plan.mode,
        "level": level,
        "attempt": 1,
        "seed": run_seed,
        "level_seed": level_seed,
        "outcome": outcome,
        "started_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "duration_s": round(play.t, 2),
        "map": play.sample_map.data,
        "path": play.path,
        "events": play.events,
        "weapons_used": play.weapons_used,
        "difficulty_index": None if plan.mode == "demo" else PLANNED_INDEX.get(level),
    }


def _shop(rng: random.Random, state: dict[str, Any], add: Any) -> None:
    """The shop on the level-completed screen, between two levels."""
    damage_price = DAMAGE_BASE_PRICE + DAMAGE_PRICE_STEP * state["damage_bought"]
    if state["damage_bought"] < MAX_DAMAGE_BONUS and state["coins"] >= damage_price and rng.random() < 0.7:
        state["coins"] -= damage_price
        state["damage_bought"] += 1
        add("item_bought", item="damage", price=damage_price)
    if state["coins"] >= LIFE_PRICE and state["lives"] < MAX_LIVES and rng.random() < 0.5:
        state["coins"] -= LIFE_PRICE
        state["lives"] += 1
        add("item_bought", item="life", price=LIFE_PRICE)
    if state["coins"] >= WEAPON_PRICE and rng.random() < 0.2:
        state["coins"] -= WEAPON_PRICE
        state["weapon"] = rng.choice(SHOP_WEAPONS)
        add("item_bought", item=state["weapon"], price=WEAPON_PRICE)


def sample_run(repo: SqliteStatsRepository, rng: random.Random, maps: dict[str, dict[str, Any]], plan: RunPlan) -> None:
    """Creates one run with its events and level files (and finishes it)."""
    run_seed = rng.randrange(2**32)
    repo.create_run(RunCreate(id=plan.run_id, player_name=plan.player, mode=plan.mode,
                              run_seed=run_seed, started_at=plan.started))
    demo = plan.mode == "demo"
    state = {"lives": DEMO_LIVES if demo else STARTING_LIVES, "weapon": START_WEAPON,
             "coins": 0, "damage_bought": 0, "score": 0, "kills": 0}
    events: list[EventIn] = []
    t_run = 0.0
    level = 1

    def add(kind: str, at: float | None = None, **payload: Any) -> None:
        moment = t_run if at is None else at
        events.append(EventIn(seq=len(events), type=kind, level=level, t_run_s=round(moment, 2),
                              payload=payload, at=plan.started + timedelta(seconds=moment)))

    last_level = 1 if demo else MAX_LEVEL
    if not plan.finished:
        last_level = rng.randint(2, 3)
    outcome = "completed"
    for level in range(1, last_level + 1):
        if demo:
            sample_map, level_seed = SampleMap.from_data(maps[DEMO_MAP]), None
        else:
            sample_map, level_seed = _pick_map(rng, maps, level)
        if not plan.finished and level == last_level:
            # The level being played now has no file yet: it is written when it ends.
            add("level_started", lives=state["lives"], enemies_total=6 + level * 2)
            break
        # A run still in progress has only cleared levels behind it.
        outcome = _level_outcome(rng, plan, level) if plan.finished else "completed"
        play = play_level(rng, sample_map, level, state["lives"], state["weapon"], plan.skill, outcome, demo)
        enemies_total = play.kills + rng.randint(0, 3)
        add("level_started", lives=state["lives"], enemies_total=enemies_total)
        for t, kind, payload in play.run_events:
            if kind == "enemy_killed":
                state["score"] += POINTS_PER_KILL
                state["kills"] += 1
            elif kind == "coin_picked":
                state["coins"] += payload["amount"]
            add(kind, at=t_run + t, **payload)
        level_started_at = plan.started + timedelta(seconds=t_run)
        t_run += play.t
        state["lives"], state["weapon"] = play.lives, play.weapon
        raw = _level_file(plan, play, level, level_seed, outcome, run_seed, level_started_at)
        repo.add_level_track(plan.run_id, LevelTrackIn.model_validate(raw), raw)
        if outcome == "died":
            add("player_died", score=state["score"], cause=play.events[-1]["cause"])
            break
        if outcome == "abandoned" or level == last_level:
            add("run_quit", score=state["score"])
            break
        state["score"] += POINTS_PER_LEVEL
        add("level_completed", duration_s=round(play.t, 2), kills=play.kills,
            enemies_total=enemies_total, score=state["score"])
        _shop(rng, state, add)
        t_run += rng.uniform(4, 12)  # level-completed screen and shop
    repo.add_events(plan.run_id, events)
    if plan.finished:
        repo.finish_run(plan.run_id, RunFinish(
            outcome="died" if outcome == "died" else "quit",
            score=state["score"],
            level_reached=level,
            enemies_killed=state["kills"],
            duration_s=round(t_run, 1),
            ended_at=plan.started + timedelta(seconds=t_run),
        ))


def run_plans(rng: random.Random, now: datetime) -> list[RunPlan]:
    """Every sample run, oldest first per player: the first run is often the
    demo and about one in eight is a test run."""
    plans = []
    for player, (count, skill) in SAMPLE_PLAYERS.items():
        for index in range(count):
            days_ago = HISTORY_DAYS * (1 - index / count) - rng.uniform(0, 1)
            started = (now - timedelta(days=max(days_ago, 0.05))).replace(microsecond=0)
            if index == 0 and rng.random() < 0.7:
                mode = "demo"
            elif rng.random() < 0.12:
                mode = "test"
            else:
                mode = "normal"
            newest = index == count - 1
            plans.append(RunPlan(f"{SEED_PREFIX}{player.lower()}-{index:02d}", player, mode, skill,
                                 started, finished=not (newest and player == PLAYER_IN_PROGRESS)))
    return plans


def seed(db_path: Path) -> int:
    database.initialize(db_path)
    conn = database.connect(db_path)
    try:
        repo = SqliteStatsRepository(conn)
        rng = random.Random(42)
        maps = load_maps()
        plans = run_plans(rng, datetime.now(UTC))
        for plan in plans:
            sample_run(repo, rng, maps, plan)
        return len(plans)
    finally:
        conn.close()


def remove(db_path: Path) -> int:
    """Delete the sample runs (with their events and level files) and the
    sample players left without runs."""
    database.initialize(db_path)
    conn = database.connect(db_path)
    try:
        with conn:
            deleted = conn.execute("DELETE FROM runs WHERE id LIKE ?", (f"{SEED_PREFIX}%",)).rowcount
            names = list(SAMPLE_PLAYERS)
            placeholders = ",".join("?" * len(names))
            conn.execute(
                f"DELETE FROM players WHERE name IN ({placeholders}) "
                "AND id NOT IN (SELECT player_id FROM runs)",
                names,
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
