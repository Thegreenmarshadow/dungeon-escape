// Level maps drawn with the game's tileset. A map is the server's view of a
// level map (level_maps.view_map): size [w, h] in cells of cell_px world
// pixels, origin, cells (one digit per cell: 0 empty, 1 floor, 2 wall) and
// the start, key and door cells.

const TILE = 16;

const imageCache = new Map();

/** Loads an image once; later calls share the same promise. */
export function loadImage(src) {
  if (!imageCache.has(src)) {
    imageCache.set(src, new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error(`no se pudo cargar ${src}`));
      image.src = src;
    }));
  }
  return imageCache.get(src);
}

export async function loadSprites() {
  const [tileset, key, heart] = await Promise.all([
    loadImage("assets/tiles/tileset.png"),
    loadImage("assets/icons/key.png"),
    loadImage("assets/icons/heart.png"),
  ]);
  return { tileset, key, heart };
}

// Tiles of Dungeon_Tileset.png ([column, row] of 16 px), chosen like an
// autotile from where the floor is around each wall cell.
const FLOOR_TILES = [[6, 0], [7, 0], [8, 0], [9, 0], [6, 1], [7, 1], [8, 1], [9, 1], [6, 2], [7, 2], [8, 2], [9, 2]];
const WALL_ABOVE_FLOOR = [[1, 0], [2, 0], [3, 0], [4, 0]];
const WALL_BELOW_FLOOR = [[1, 4], [2, 4], [3, 4], [4, 4]];
const WALL_LEFT_OF_FLOOR = [[0, 1], [0, 2], [0, 3]];
const WALL_RIGHT_OF_FLOOR = [[5, 1], [5, 2], [5, 3]];
const CORNERS = [
  [1, 1, [0, 0]], [-1, 1, [5, 0]], [1, -1, [0, 4]], [-1, -1, [5, 4]],
];

function pick(tiles, x, y) {
  return tiles[Math.abs((x * 73856093) ^ (y * 19349663)) % tiles.length];
}

export function mapSize(map) {
  const [w = 0, h = 0] = map?.size || [];
  return [w, h];
}

/** The world rectangle the map grid covers ({x, y, w, h}); null without size. */
export function mapRect(map) {
  const [w, h] = mapSize(map);
  if (w <= 0 || h <= 0) return null;
  const cell = map.cell_px || TILE;
  const [ox, oy] = map.origin || [0, 0];
  return { x: ox, y: oy, w: w * cell, h: h * cell };
}

/** World pixel of the center of a cell, like LevelSnapshot.cell_to_world. */
export function cellCenter(map, cell) {
  const size = map.cell_px || TILE;
  const [ox, oy] = map.origin || [0, 0];
  return [ox + (cell[0] + 0.5) * size, oy + (cell[1] + 0.5) * size];
}

/** An offscreen canvas with the map at one tile (16 px) per cell. */
export function mapImage(map, tileset) {
  const [w, h] = mapSize(map);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(w * TILE, 1);
  canvas.height = Math.max(h * TILE, 1);
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  const cells = map.cells || "";
  const at = (x, y) => (x < 0 || y < 0 || x >= w || y >= h ? "0" : cells[y * w + x]);
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      const kind = at(x, y);
      let tile = null;
      if (kind === "1") tile = pick(FLOOR_TILES, x, y);
      else if (kind === "2") {
        if (at(x, y + 1) === "1") tile = pick(WALL_ABOVE_FLOOR, x, y);
        else if (at(x, y - 1) === "1") tile = pick(WALL_BELOW_FLOOR, x, y);
        else if (at(x + 1, y) === "1") tile = pick(WALL_LEFT_OF_FLOOR, x, y);
        else if (at(x - 1, y) === "1") tile = pick(WALL_RIGHT_OF_FLOOR, x, y);
        else tile = (CORNERS.find(([dx, dy]) => at(x + dx, y + dy) === "1") || [0, 0, [0, 0]])[2];
      }
      if (tile) ctx.drawImage(tileset, tile[0] * TILE, tile[1] * TILE, TILE, TILE, x * TILE, y * TILE, TILE, TILE);
    }
  }
  return canvas;
}

/** Uniform scale and offset that fit the world rectangle in the view with a
 * margin, centered (RouteReplay.fit). */
export function fit(world, viewW, viewH, margin = 0) {
  const availableW = Math.max(viewW - margin * 2, 1);
  const availableH = Math.max(viewH - margin * 2, 1);
  const scale = Math.min(availableW / Math.max(world.w, 1), availableH / Math.max(world.h, 1));
  return {
    scale,
    ox: (viewW - world.w * scale) / 2 - world.x * scale,
    oy: (viewH - world.h * scale) / 2 - world.y * scale,
  };
}

/** A canvas that follows the size of its box at the screen's pixel density.
 * draw(ctx, width, height) runs on every resize and on redraw(). */
export function hiDpiCanvas(box, heightFor, draw) {
  const canvas = document.createElement("canvas");
  box.append(canvas);
  let width = 0;
  let height = 0;
  function redraw() {
    if (!width || !height) return;
    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw(ctx, width, height);
  }
  const observer = new ResizeObserver((entries) => {
    if (!canvas.isConnected) {
      observer.disconnect();
      return;
    }
    const newWidth = Math.floor(entries[0].contentRect.width);
    if (newWidth === width) return;
    requestAnimationFrame(() => {
      width = newWidth;
      height = Math.round(heightFor(width));
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.height = `${height}px`;
      redraw();
    });
  });
  observer.observe(box);
  return { canvas, redraw, size: () => [width, height] };
}

/** Draws the map image into the world rectangle with the view transform. */
export function drawMap(ctx, image, map, view) {
  const rect = mapRect(map);
  if (!rect || !image) return;
  // Shrinking pixel art needs smoothing; growing it must stay crisp.
  ctx.imageSmoothingEnabled = view.scale * (window.devicePixelRatio || 1) < 1;
  ctx.drawImage(image, view.ox + rect.x * view.scale, view.oy + rect.y * view.scale, rect.w * view.scale, rect.h * view.scale);
  ctx.imageSmoothingEnabled = false;
}
