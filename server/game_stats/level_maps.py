"""Maps of the level telemetry files the game uploads (Telemetry autoload).

Mirrors the game's TelemetryStore / LevelSnapshot helpers so the server and
the in-game reports read the same data the same way:

- ``map.size`` is ``[width, height]`` in cells of ``map.cell_px`` world pixels;
  ``map.origin`` is the world pixel of the top-left corner of cell ``[0, 0]``.
- ``map.floor`` is a run-length encoding, row-major (``y * width + x``), of
  comma-separated run lengths alternating non-floor / floor, starting with
  non-floor (``"3,2,1"`` -> ``0 0 0 1 1 0``).
- Walls are not stored: a wall is any non-floor cell touching floor in its
  8-neighbourhood (``LevelGenerator.Layout.is_wall``).
"""

import hashlib
import math
from typing import Any

CELL_PX = 16
EMPTY, FLOOR, WALL = 0, 1, 2


def map_size(level_map: dict[str, Any]) -> tuple[int, int]:
    size = level_map.get("size")
    if isinstance(size, list) and len(size) >= 2:
        try:
            return max(int(size[0]), 0), max(int(size[1]), 0)
        except (TypeError, ValueError):
            pass
    return 0, 0


def cell_px(level_map: dict[str, Any]) -> float:
    try:
        return float(max(int(level_map.get("cell_px", CELL_PX)), 1))
    except (TypeError, ValueError):
        return float(CELL_PX)


def origin(level_map: dict[str, Any]) -> tuple[float, float]:
    raw = level_map.get("origin")
    if isinstance(raw, list) and len(raw) >= 2:
        try:
            return float(raw[0]), float(raw[1])
        except (TypeError, ValueError):
            pass
    return 0.0, 0.0


def map_cell(level_map: dict[str, Any], key: str) -> tuple[int, int] | None:
    """Cell stored under "door", "key" or "start"; None if missing."""
    value = level_map.get(key)
    if isinstance(value, list) and len(value) >= 2:
        try:
            return int(value[0]), int(value[1])
        except (TypeError, ValueError):
            return None
    return None


def decode_floor(level_map: dict[str, Any]) -> bytearray:
    """One byte per cell (index y * width + x), 1 = floor. Tolerant like the
    game: runs past the grid are cut and missing cells stay non-floor."""
    width, height = map_size(level_map)
    count = width * height
    cells = bytearray(count)
    index, bit = 0, 0
    for part in str(level_map.get("floor", "")).split(","):
        if part == "":
            continue
        try:
            length = max(int(part), 0)
        except ValueError:
            length = 0
        if bit == 1:
            end = min(index + length, count)
            if end > index:
                cells[index:end] = b"\x01" * (end - index)
        index += length
        bit = 1 - bit
        if index >= count:
            break
    return cells


def cell_grid(level_map: dict[str, Any]) -> str:
    """The map as one digit per cell, row-major: 0 empty, 1 floor, 2 wall."""
    width, height = map_size(level_map)
    floor = decode_floor(level_map)
    out = bytearray(b"0" * (width * height))
    for y in range(height):
        row = y * width
        for x in range(width):
            index = row + x
            if floor[index]:
                out[index] = ord("1")
            elif _touches_floor(floor, width, height, x, y):
                out[index] = ord("2")
    return out.decode("ascii")


def _touches_floor(floor: bytearray, width: int, height: int, x: int, y: int) -> bool:
    for dy in (-1, 0, 1):
        ny = y + dy
        if ny < 0 or ny >= height:
            continue
        for dx in (-1, 0, 1):
            nx = x + dx
            if 0 <= nx < width and floor[ny * width + nx]:
                return True
    return False


def world_to_cell(level_map: dict[str, Any], x: float, y: float) -> tuple[int, int]:
    """Grid cell that contains the world pixel (x, y)."""
    size = cell_px(level_map)
    ox, oy = origin(level_map)
    return math.floor((x - ox) / size), math.floor((y - oy) / size)


def view_map(level_map: dict[str, Any]) -> dict[str, Any]:
    """What the web page needs to draw a map: the grid already decoded."""
    width, height = map_size(level_map)
    return {
        "size": [width, height],
        "cell_px": cell_px(level_map),
        "origin": list(origin(level_map)),
        "cells": cell_grid(level_map),
        "door": map_cell(level_map, "door"),
        "key": map_cell(level_map, "key"),
        "start": map_cell(level_map, "start"),
    }


def map_key(level: int, level_map: dict[str, Any]) -> str:
    """Identity of a level's map: level number plus a fingerprint of the stored
    map (size, floor, door and key), like PatternAnalysis.map_key. Two runs
    with the same level seed share it; the hand-made level 1 always does."""
    fingerprint = "|".join(
        str(level_map.get(key)) for key in ("size", "floor", "door", "key")
    )
    digest = hashlib.sha1(fingerprint.encode("utf-8")).hexdigest()[:16]
    return f"{level}|{digest}"


def map_label(level: int, mode: str, level_seed: Any) -> str:
    """Readable name of a map, like PatternAnalysis.map_label."""
    if mode == "demo":
        return "Demo"
    if isinstance(level_seed, str) and level_seed:
        return f"Nivel {level} · semilla {level_seed}"
    if level == 1:
        return "Nivel 1 (hecho a mano)"
    return f"Nivel {level}"
