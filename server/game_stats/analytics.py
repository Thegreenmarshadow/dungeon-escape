"""Analytics over uploaded level telemetry: per-level stats, automatic warnings,
planned vs measured difficulty and heatmaps per map.

Pure functions over level dicts (the JSON files the game writes, see
level_maps). They port the game's analytics scripts so the web page and the
in-game reports agree; keep them in sync:

- level_stats      scripts/analytics/level_stats.gd    (LevelStats)
- insights         scripts/analytics/insights.gd       (AnalyticsInsights)
- heatmaps         scripts/analytics/pattern_analysis.gd (PatternAnalysis)
- track_summary    scripts/analytics/run_summary.gd    (side panel)
"""

import math
from typing import Any

from . import level_maps

# --- LevelStats --------------------------------------------------------------

# The demo is a hand-made map different from the normal level 1 and revives the
# player, so it stays out of the per-level stats (unless it is asked for).
EXCLUDED_MODES = ("demo",)
WEIGHT_DEATHS = 0.5
WEIGHT_DAMAGE = 0.5
UNKNOWN_SOURCE = "unknown"
CHART_MIN_LAST_LEVEL = 10
LAST_LEVEL = 100  # DifficultyCurve.LAST_LEVEL
FINISHED_OUTCOMES = ("completed", "died", "abandoned")
# The player's damage and healing ("amount") and health ("lives") come in
# hearts. Since the game counts health in half hearts they can be fractional
# (0.5, 1.5); older files have whole hearts, so both stay comparable. A damage
# event counts at least half a heart.
MIN_DAMAGE_HEARTS = 0.5

# --- AnalyticsInsights thresholds ---------------------------------------------

MIN_ATTEMPTS = 5
MIN_DEATHS_FOR_CAUSE = 3
DEATH_RATE_WARN = 0.40
CAUSE_SHARE_WARN = 0.50
ABANDON_RATE_WARN = 0.40
TIME_RATIO_WARN = 2.5
DAMAGE_RATIO_WARN = 2.0

# Spanish name of each damage source or death cause (AnalyticsInsights).
SOURCE_NAMES = {
    "spikes": "picos",
    "Skeleton": "esqueletos",
    "Vampire": "vampiros",
    "Skull": "calaveras",
    "Archer": "arqueros",
    "SkullTurret": "torres de calaveras",
    "Mimic": "mímicos",
    "Mage": "magos",
    "Reaper": "la parca",
    "Forge": "el Forjador",
    "forge": "peligros del Forjador",
    "Lich": "el liche",
    "lich": "peligros del liche",
    "Warden": "el Guardián",
    "warden": "peligros del Guardián",
    "projectile": "proyectiles",
    "boss_hazard": "peligros de jefe",
    "unknown": "causa desconocida",
}

# --- PatternAnalysis layers ----------------------------------------------------

LAYER_TIME = "time"
LAYER_DAMAGE = "damage"
LAYER_DEATHS = "deaths"
HEAT_LAYERS = (LAYER_TIME, LAYER_DAMAGE, LAYER_DEATHS)
# Map groups returned at most (the ones with more attempts first).
MAX_HEATMAP_GROUPS = 12


def source_name(value: Any) -> str:
    """Name of a damage source or death cause; empty means UNKNOWN_SOURCE."""
    text = "" if value is None else str(value).strip()
    return text or UNKNOWN_SOURCE


def source_label(source: str) -> str:
    return SOURCE_NAMES.get(source, source)


def _ratio(a: float, b: float) -> float:
    return a / b if b > 0 else 0.0


def _round_half_away(value: float) -> int:
    """Godot's roundi: halves go away from zero (Python's round() goes to even)."""
    return int(math.floor(abs(value) + 0.5)) * (1 if value >= 0 else -1)


def _events(data: dict[str, Any]) -> list[dict[str, Any]]:
    events = data.get("events")
    return [e for e in events if isinstance(e, dict)] if isinstance(events, list) else []


def _num(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)) and math.isfinite(value):
        return float(value)
    return default


def _int(value: Any, default: int = 0) -> int:
    """Like Godot's int(): truncates toward zero."""
    return int(_num(value, default))


def _event_hearts(event: dict[str, Any]) -> float:
    """Hearts lost (damage event) or healed (heart event): its amount, 1 if it
    has none and at least MIN_DAMAGE_HEARTS."""
    return max(_num(event.get("amount"), 1.0), MIN_DAMAGE_HEARTS)


# --- Per-level stats -----------------------------------------------------------


def level_stats(levels: list[dict[str, Any]], excluded_modes: tuple[str, ...] = EXCLUDED_MODES) -> list[dict[str, Any]]:
    """One row per level, sorted by level (LevelStats.aggregate). Ignores files
    that did not finish and the excluded modes."""
    by_level: dict[int, dict[str, Any]] = {}
    for data in levels:
        outcome = str(data.get("outcome", ""))
        if outcome not in FINISHED_OUTCOMES or str(data.get("mode", "")) in excluded_modes:
            continue
        level = _int(data.get("level"))
        row = by_level.setdefault(level, _empty_row(level))
        _add_level_file(row, data)
    rows = [_finish_row(by_level[level]) for level in sorted(by_level)]
    apply_measured_difficulty(rows)
    return rows


def _empty_row(level: int) -> dict[str, Any]:
    return {
        "level": level,
        "attempts": 0,
        "completed": 0,
        "died": 0,
        "abandoned": 0,
        "deaths": 0,
        "deaths_by_cause": {},
        "total_time_s": 0.0,
        "damage_total": 0.0,
        "damage_by_source": {},
        "weapons_used": [],
    }


def _add_level_file(row: dict[str, Any], data: dict[str, Any]) -> None:
    row["attempts"] += 1
    outcome = str(data.get("outcome", ""))
    if outcome in ("completed", "died", "abandoned"):
        row[outcome] += 1
    row["total_time_s"] += max(_num(data.get("duration_s")), 0.0)
    for event in _events(data):
        kind = event.get("type")
        if kind == "damage":
            amount = _num(event.get("amount"))
            source = source_name(event.get("source"))
            row["damage_total"] += amount
            row["damage_by_source"][source] = row["damage_by_source"].get(source, 0) + amount
        elif kind == "death":
            cause = source_name(event.get("cause"))
            row["deaths"] += 1
            row["deaths_by_cause"][cause] = row["deaths_by_cause"].get(cause, 0) + 1
    weapons = data.get("weapons_used")
    if isinstance(weapons, list):
        for weapon in weapons:
            weapon_id = str(weapon)
            if weapon_id and weapon_id not in row["weapons_used"]:
                row["weapons_used"].append(weapon_id)


def _finish_row(row: dict[str, Any]) -> dict[str, Any]:
    attempts = row["attempts"]
    row["completion_rate"] = _ratio(row["completed"], attempts)
    row["death_rate"] = _ratio(row["died"], attempts)
    row["abandon_rate"] = _ratio(row["abandoned"], attempts)
    row["mean_time_s"] = _ratio(row["total_time_s"], attempts)
    row["damage_per_min"] = _ratio(row["damage_total"], row["total_time_s"] / 60.0)
    row["deaths_per_attempt"] = _ratio(row["deaths"], attempts)
    top = top_death_cause(row)
    row["top_death_cause"] = top["cause"]
    row["top_death_share"] = top["share"]
    return row


def measured_difficulty(deaths_per_attempt: float, damage_per_min: float, max_deaths: float, max_damage: float) -> float:
    """50 % deaths per attempt + 50 % damage per minute, each divided by its
    maximum among the levels analyzed together (the hardest level is 1)."""
    return WEIGHT_DEATHS * _ratio(deaths_per_attempt, max_deaths) + WEIGHT_DAMAGE * _ratio(damage_per_min, max_damage)


def apply_measured_difficulty(rows: list[dict[str, Any]]) -> None:
    max_deaths = max((row["deaths_per_attempt"] for row in rows), default=0.0)
    max_damage = max((row["damage_per_min"] for row in rows), default=0.0)
    for row in rows:
        row["deaths_norm"] = _ratio(row["deaths_per_attempt"], max_deaths)
        row["damage_norm"] = _ratio(row["damage_per_min"], max_damage)
        row["measured_difficulty"] = measured_difficulty(
            row["deaths_per_attempt"], row["damage_per_min"], max_deaths, max_damage
        )


def top_death_cause(row: dict[str, Any]) -> dict[str, Any]:
    """Cause with most deaths ({cause, count, share}); ties go to the first in
    alphabetical order. cause is "" without deaths."""
    best, best_count = "", 0
    causes = row["deaths_by_cause"]
    for cause in sorted(causes):
        if causes[cause] > best_count:
            best, best_count = cause, causes[cause]
    return {"cause": best, "count": best_count, "share": _ratio(best_count, row["deaths"])}


# --- Warnings --------------------------------------------------------------------


def insights(rows: list[dict[str, Any]]) -> list[str]:
    """Automatic warnings in Spanish, by level (AnalyticsInsights.generate_from_stats)."""
    lines: list[str] = []
    if not rows:
        return lines
    by_level = {row["level"]: row for row in rows}
    enough = 0
    for row in rows:
        if row["attempts"] < MIN_ATTEMPTS:
            continue
        enough += 1
        level = row["level"]
        death_line = _death_warning(row)
        if death_line:
            lines.append(death_line)
        if row["abandon_rate"] >= ABANDON_RATE_WARN:
            lines.append(f"Nivel {level}: {_pct(row['abandon_rate'])} % abandona sin terminar")
        previous = by_level.get(level - 1)
        if previous is None or previous["attempts"] < MIN_ATTEMPTS:
            continue
        if previous["mean_time_s"] > 0:
            time_ratio = row["mean_time_s"] / previous["mean_time_s"]
            if time_ratio >= TIME_RATIO_WARN:
                lines.append(f"Nivel {level}: tiempo medio {_times(time_ratio)} el del nivel {level - 1}")
        if previous["damage_per_min"] > 0:
            damage_ratio = row["damage_per_min"] / previous["damage_per_min"]
            if damage_ratio >= DAMAGE_RATIO_WARN:
                lines.append(f"Nivel {level}: daño por minuto {_times(damage_ratio)} el del nivel {level - 1}")
    if enough == 0:
        lines.append(
            f"Sin avisos todavía: ningún nivel llega a {MIN_ATTEMPTS} intentos (hay {len(rows)} niveles con menos)."
        )
    return lines


def _death_warning(row: dict[str, Any]) -> str:
    if row["death_rate"] < DEATH_RATE_WARN:
        return ""
    text = f"Nivel {row['level']}: {_pct(row['death_rate'])} % muere"
    top = top_death_cause(row)
    if row["deaths"] >= MIN_DEATHS_FOR_CAUSE and top["share"] >= CAUSE_SHARE_WARN:
        text += f", el {_pct(top['share'])} % por {source_label(top['cause'])}"
    return text


def _pct(rate: float) -> int:
    return _round_half_away(rate * 100.0)


def _times(ratio: float) -> str:
    """"3×" for almost whole values, "2.5×" otherwise."""
    rounded = _round_half_away(ratio * 10.0) / 10.0
    if math.isclose(rounded, round(rounded), abs_tol=1e-6):
        return f"{_round_half_away(rounded)}×"
    return f"{rounded:.1f}×"


# --- Planned vs measured difficulty ------------------------------------------------


def planned_indexes(levels: list[dict[str, Any]]) -> dict[int, float]:
    """Planned difficulty index per level, from the difficulty_index field the
    game writes (DifficultyCurve.index_for). Files without it are skipped; with
    several values for a level (different game versions) the last one wins."""
    planned: dict[int, float] = {}
    for data in levels:
        value = data.get("difficulty_index")
        if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
            planned[_int(data.get("level"))] = float(value)
    return planned


def chart_rows(rows: list[dict[str, Any]], planned: dict[int, float], last_level: int = -1) -> list[dict[str, Any]]:
    """One point per level from 1 to the last level with data (at least
    CHART_MIN_LAST_LEVEL), like LevelStats.chart_rows: planned is the index
    divided by the highest one in the range (None without a value), measured
    the measured difficulty (None without attempts)."""
    by_level = {row["level"]: row for row in rows}
    last = max([CHART_MIN_LAST_LEVEL, *by_level.keys()])
    if last_level > 0:
        last = last_level
    last = min(max(last, 1), LAST_LEVEL)
    points = []
    for level in range(1, last + 1):
        row = by_level.get(level)
        points.append({
            "level": level,
            "planned_raw": planned.get(level),
            "measured": row["measured_difficulty"] if row else None,
            "attempts": row["attempts"] if row else 0,
        })
    max_planned = max((p["planned_raw"] for p in points if p["planned_raw"] is not None), default=0.0)
    for point in points:
        raw = point["planned_raw"]
        point["planned"] = None if raw is None else _ratio(raw, max_planned)
    return points


# --- Heatmaps per map --------------------------------------------------------------


def weighted_points(data: dict[str, Any], layer: str) -> list[tuple[float, float, float]]:
    """(x, y, weight) in world pixels for one layer of a level file."""
    points: list[tuple[float, float, float]] = []
    if layer == LAYER_TIME:
        path = [p for p in data.get("path") or [] if isinstance(p, list) and len(p) >= 3]
        duration = _num(data.get("duration_s"))
        for i, sample in enumerate(path):
            t = _num(sample[0])
            next_t = _num(path[i + 1][0]) if i + 1 < len(path) else max(duration, t)
            weight = max(next_t - t, 0.0)
            if weight > 0:
                points.append((_num(sample[1]), _num(sample[2]), weight))
    elif layer == LAYER_DAMAGE:
        for event in _events(data):
            if event.get("type") == "damage":
                points.append((_num(event.get("x")), _num(event.get("y")), _event_hearts(event)))
    elif layer == LAYER_DEATHS:
        for event in _events(data):
            if event.get("type") == "death":
                points.append((_num(event.get("x")), _num(event.get("y")), 1.0))
    return points


def heat_grid(level_map: dict[str, Any], levels: list[dict[str, Any]], layer: str) -> dict[int, float]:
    """Sparse heatmap {cell index: value}; what falls outside the grid is dropped."""
    width, height = level_maps.map_size(level_map)
    grid: dict[int, float] = {}
    for data in levels:
        for x, y, weight in weighted_points(data, layer):
            cx, cy = level_maps.world_to_cell(level_map, x, y)
            if 0 <= cx < width and 0 <= cy < height:
                index = cy * width + cx
                grid[index] = grid.get(index, 0.0) + weight
    return grid


def group_by_map(levels: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Level files grouped by map (map_key): the group with more files first, then
    by level and label. Repeated labels (a level that changed between versions)
    are numbered, like PatternAnalysis.group_by_map."""
    groups: dict[str, dict[str, Any]] = {}
    for data in levels:
        level_map = data.get("map") if isinstance(data.get("map"), dict) else {}
        level = _int(data.get("level"))
        key = level_maps.map_key(level, level_map)
        group = groups.get(key)
        if group is None:
            group = groups[key] = {
                "key": key,
                "label": level_maps.map_label(level, str(data.get("mode", "")), data.get("level_seed")),
                "level": level,
                "map": level_map,
                "levels": [],
            }
        group["levels"].append(data)
    ordered = sorted(groups.values(), key=lambda g: (-len(g["levels"]), g["level"], g["label"]))
    seen: dict[str, int] = {}
    for group in ordered:
        label = group["label"]
        seen[label] = seen.get(label, 0) + 1
        if seen[label] > 1:
            group["label"] = f"{label} (mapa {seen[label]})"
    return ordered


def heatmaps(levels: list[dict[str, Any]], max_groups: int = MAX_HEATMAP_GROUPS) -> list[dict[str, Any]]:
    """Heatmaps of time, damage and deaths for each map, ready for the web page."""
    out = []
    for group in group_by_map(levels)[:max_groups]:
        layers, totals = {}, {}
        for layer in HEAT_LAYERS:
            grid = heat_grid(group["map"], group["levels"], layer)
            layers[layer] = [[index, round(value, 3)] for index, value in sorted(grid.items())]
            totals[layer] = round(sum(grid.values()), 3)
        out.append({
            "key": group["key"],
            "label": group["label"],
            "level": group["level"],
            "attempts": len(group["levels"]),
            "map": level_maps.view_map(group["map"]),
            "layers": layers,
            "totals": totals,
        })
    return out


# --- One level of one run -----------------------------------------------------------


def track_summary(data: dict[str, Any]) -> dict[str, Any]:
    """Side panel of the route view: damage by source, death causes and counts."""
    damage: dict[str, float] = {}
    causes: dict[str, int] = {}
    counts: dict[str, float] = {"kills": 0, "hearts": 0, "attacks": 0, "hits": 0, "keys": 0}
    for event in _events(data):
        kind = event.get("type")
        if kind == "damage":
            source = source_name(event.get("source"))
            damage[source] = damage.get(source, 0) + _event_hearts(event)
        elif kind == "death":
            cause = source_name(event.get("cause"))
            causes[cause] = causes.get(cause, 0) + 1
        elif kind == "enemy_killed":
            counts["kills"] += 1
        elif kind == "heart":
            counts["hearts"] += _event_hearts(event)
        elif kind == "key":
            counts["keys"] += 1
        elif kind == "attack":
            counts["attacks"] += 1
            counts["hits"] += 1 if event.get("hit") is True else 0
    return {
        "damage_by_source": _labelled(damage),
        "deaths_by_cause": _labelled(causes),
        **counts,
    }


def _labelled(values: dict[str, int] | dict[str, float]) -> list[dict[str, Any]]:
    """[{source, label, count}] from most to least, then by name."""
    return [
        {"source": source, "label": source_label(source), "count": count}
        for source, count in sorted(values.items(), key=lambda item: (-item[1], item[0]))
    ]


def source_labels(rows: list[dict[str, Any]]) -> dict[str, str]:
    """Spanish label of every source and cause that appears in the rows."""
    labels: dict[str, str] = {}
    for row in rows:
        for source in (*row["damage_by_source"], *row["deaths_by_cause"]):
            labels[source] = source_label(source)
    return labels
