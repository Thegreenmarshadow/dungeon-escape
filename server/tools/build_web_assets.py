"""Copy and cut the game's pixel art into server/web/assets.

The web page uses the game's own sprites and tiles, but the server must work
without the Godot project next to it, so the images it needs are committed
under server/web/assets. This script rebuilds them from the game's assets/
folder when the art changes:

    cd server && uv run --no-project --with pillow python tools/build_web_assets.py

It only reads ../assets and only writes server/web/assets (fonts excepted:
they are OFL files downloaded by hand, see assets/fonts/).
"""

import shutil
from pathlib import Path

from PIL import Image

SERVER_DIR = Path(__file__).resolve().parent.parent
GAME_ASSETS = SERVER_DIR.parent / "assets"
OUT = SERVER_DIR / "web" / "assets"
TILE = 16

TILESETS = {
    "": "dungeon/character_and_tileset/Dungeon_Tileset.png",
    "-ice": "dungeon/character_and_tileset/Dungeon_Tileset_ice.png",
    "-lava": "dungeon/character_and_tileset/Dungeon_Tileset_lava.png",
    "-moss": "dungeon/character_and_tileset/Dungeon_Tileset_moss.png",
}
# The small room at the top-left of the tileset, from the outer stone band:
# 16 px of wall on top, a 7 px band on the sides and bottom (the page uses it
# as a 9-slice border-image).
FRAME_BOX = (9, 0, 87, 71)
FLOOR_BOX = (96, 0, 160, 48)
WALL_BOX = (16, 0, 80, 16)
SKULL_TILE = (7, 7)
CHARACTERS = "dungeon/character_and_tileset/Dungeon_Character.png"
# Dungeon_Character.png marks the corners of every 16 px cell with a 3 px
# bracket (cyan on heroes, red on monsters); avatars look cleaner without it.
CORNER_MARKS = ((0, 0), (1, 0), (0, 1))

# Heart pickup, drawn like scripts/heart.gd: "o" outline, "r" fill, "h" shine.
HEART_PATTERN = (
    ".oo...oo.",
    "ohro.orro",
    "ohrrorrro",
    "orrrrrrro",
    ".orrrrro.",
    "..orrro..",
    "...oro...",
    "....o....",
)
HEART_COLORS = {"o": (61, 10, 18, 255), "r": (217, 38, 51, 255), "h": (255, 158, 158, 255)}

# Enemy and boss icons are cut to this square around the sprite (bosses are
# halved from 48 px), so every damage source icon is 16 or 24 px.
SOURCE_ICON = 24

# Single frames: output name -> (source, crop box or None for the whole image).
ICONS = {
    "coin": ("dungeon/items_and_traps/coin/coin_1.png", None),
    "key": ("dungeon/items_and_traps/keys/keys_1_1.png", None),
    "spikes": ("dungeon/items_and_traps/peaks/peaks_1.png", None),
    "chest": ("dungeon/items_and_traps/chest/chest_1.png", None),
    "flag": ("dungeon/items_and_traps/flag/flag_1.png", None),
    "torch": ("dungeon/items_and_traps/torch/torch_1.png", None),
    "candle": ("dungeon/items_and_traps/torch/candlestick_1_1.png", None),
    "flask": ("dungeon/items_and_traps/flasks/flasks_1_1.png", None),
    "orb": ("projectiles/orb_gold.png", (0, 0, 16, 16)),
    "projectile": ("projectiles/orb_blue.png", (0, 0, 16, 16)),
    "skeleton": ("enemies/enemies-skeleton1_idle.png", (0, 0, 32, 32)),
    "vampire": ("enemies/enemies-vampire_idle.png", (0, 0, 32, 32)),
    "archer": ("enemies/enemies-archer_idle.png", (0, 0, 32, 32)),
    "mage": ("enemies/enemies-mage_idle.png", (0, 0, 32, 32)),
    "mimic": ("enemies/enemies-mimic_idle.png", (0, 0, 32, 32)),
    "skull-turret": ("enemies/enemies-skull_turret_idle.png", (0, 0, 32, 32)),
    "skull": (CHARACTERS, (0, 16, 16, 32)),
    "reaper": (CHARACTERS, (96, 16, 112, 32)),
    "forge": ("bosses/forge/boss-forge_idle.png", (0, 0, 48, 48)),
    "lich": ("bosses/lich/boss-lich_idle.png", (0, 0, 48, 48)),
    "warden": ("bosses/warden/boss-warden_idle.png", (0, 0, 48, 48)),
}
# Animation strips, frames side by side: output name -> frame files.
STRIPS = {
    "torch": [f"dungeon/items_and_traps/torch/torch_{i}.png" for i in range(1, 5)],
    "coin": [f"dungeon/items_and_traps/coin/coin_{i}.png" for i in range(1, 5)],
}
# Copied as they are.
COPIES = {
    "sprites/lich.png": "bosses/lich/boss-lich_idle.png",
    "sprites/forge.png": "bosses/forge/boss-forge_idle.png",
    "sprites/warden.png": "bosses/warden/boss-warden_idle.png",
    "sprites/skeleton.png": "enemies/enemies-skeleton1_idle.png",
    "tiles/tileset.png": "dungeon/character_and_tileset/Dungeon_Tileset.png",
}


def load(path: str) -> Image.Image:
    image = Image.open(GAME_ASSETS / path).convert("RGBA")
    return without_corner_marks(image) if path == CHARACTERS else image


def around_sprite(frame: Image.Image) -> Image.Image:
    """The frame cut to a square around its visible pixels: SOURCE_ICON px
    for enemies, twice that (then halved) for bosses."""
    side = SOURCE_ICON if frame.width <= 32 else SOURCE_ICON * 2
    left, top, right, bottom = frame.getbbox()
    cx, cy = (left + right) // 2, (top + bottom) // 2
    x = min(max(cx - side // 2, 0), frame.width - side)
    y = min(max(cy - side // 2, 0), frame.height - side)
    square = frame.crop((x, y, x + side, y + side))
    return square if side == SOURCE_ICON else square.resize((SOURCE_ICON, SOURCE_ICON), Image.Resampling.BOX)


def without_corner_marks(sheet: Image.Image) -> Image.Image:
    for top in range(0, sheet.height, TILE):
        for left in range(0, sheet.width, TILE):
            for dx, dy in CORNER_MARKS:
                for x, y in ((dx, dy), (TILE - 1 - dx, dy), (dx, TILE - 1 - dy), (TILE - 1 - dx, TILE - 1 - dy)):
                    sheet.putpixel((left + x, top + y), (0, 0, 0, 0))
    return sheet


def save(image: Image.Image, name: str) -> None:
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize=True)
    print(f"wrote {target.relative_to(SERVER_DIR)} {image.size[0]}x{image.size[1]}")


def build() -> None:
    for suffix, path in TILESETS.items():
        tileset = load(path)
        save(tileset.crop(FRAME_BOX), f"tiles/frame{suffix}.png")
        if not suffix:
            save(tileset.crop(FLOOR_BOX), "tiles/floor.png")
            save(tileset.crop(WALL_BOX), "tiles/wall.png")
            x, y = SKULL_TILE
            save(tileset.crop((x * TILE, y * TILE, (x + 1) * TILE, (y + 1) * TILE)), "icons/bones.png")
    save(load(CHARACTERS), "sprites/heroes.png")
    for name, (path, box) in ICONS.items():
        image = load(path)
        frame = image.crop(box) if box else image
        if frame.width > TILE:
            frame = around_sprite(frame)
        save(frame, f"icons/{name}.png")
    for name, frames in STRIPS.items():
        images = [load(frame) for frame in frames]
        strip = Image.new("RGBA", (sum(i.width for i in images), max(i.height for i in images)))
        x = 0
        for image in images:
            strip.alpha_composite(image, (x, 0))
            x += image.width
        save(strip, f"sprites/{name}.png")
    for weapon_dir in sorted((GAME_ASSETS / "weapons").iterdir()):
        icon = weapon_dir / f"{weapon_dir.name}_icon.png"
        if icon.exists():
            save(load(str(icon.relative_to(GAME_ASSETS))), f"weapons/{weapon_dir.name}.png")
    for name, path in COPIES.items():
        (OUT / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(GAME_ASSETS / path, OUT / name)
        print(f"copied {name}")
    heart = Image.new("RGBA", (len(HEART_PATTERN[0]), len(HEART_PATTERN)))
    for y, row in enumerate(HEART_PATTERN):
        for x, char in enumerate(row):
            if char in HEART_COLORS:
                heart.putpixel((x, y), HEART_COLORS[char])
    save(heart, "icons/heart.png")


if __name__ == "__main__":
    build()
