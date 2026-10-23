// Route replay of one level, like the game's RouteMapView and RouteReplay:
// the map, the whole route faint underneath, the route colored by time (blue
// at the start, yellow halfway, red at the end) up to the replay time, and
// the icons of the events. The slider and "Reproducir" replay the level.

import {
  formatDuration, formatHearts, h, heartsText, hideTooltip, icon, outcomeBadge, showTooltip, sourceIcon, weaponIcons,
} from "./dom.js";
import { ENEMY_LABELS, EVENT_LABELS, WEAPON_LABELS, sourceLabel } from "./labels.js";
import { cellCenter, drawMap, fit, hiDpiCanvas, mapImage, mapRect } from "./map-canvas.js";

const BACKGROUND = "#0d070c";
const OUTLINE = "rgb(10, 8, 13)";
const BONE = "rgb(237, 230, 209)";
const DAMAGE = "rgb(242, 38, 38)";
const DOOR = "rgb(140, 84, 38)";
const KILL = "rgb(255, 158, 38)";
const WEAPON = "rgb(77, 217, 255)";
const REVIVE = "rgb(89, 242, 115)";
const START = "rgb(77, 230, 102)";
const LOCKED = "rgb(255, 153, 38)";
const GHOST = "rgba(255, 255, 255, 0.16)";
const ROUTE_GRADIENT = [[0.25, 0.75, 1.0], [1.0, 0.9, 0.3], [1.0, 0.3, 0.25]];
// Events drawn, in order (the last ones on top). Attacks are too many to draw.
const DRAWN_EVENTS = ["weapon_changed", "heart", "enemy_killed", "key", "damage", "revive", "death"];
const ICON = 16;
const MARGIN = 12;
const PATH_ONLY_MARGIN = 32;
const PLAY_SECONDS = 12;
const HIT_RADIUS = 11;

/** Color of the route at a fraction of the level (0 start, 1 end). */
export function routeColor(fraction) {
  const f = Math.min(Math.max(fraction, 0), 1) * (ROUTE_GRADIENT.length - 1);
  const i = Math.min(Math.floor(f), ROUTE_GRADIENT.length - 2);
  const k = f - i;
  const [a, b] = [ROUTE_GRADIENT[i], ROUTE_GRADIENT[i + 1]];
  const c = a.map((v, j) => Math.round((v + (b[j] - v) * k) * 255));
  return `rgb(${c[0]}, ${c[1]}, ${c[2]})`;
}

/** Route split in continuous segments (cut at each revive, which teleports
 * the player), events sorted by time and the length of the level. */
export function buildReplay(track) {
  const events = [...(track.events || [])].sort((a, b) => (a.t || 0) - (b.t || 0));
  const breaks = new Set(events.filter((e) => e.type === "revive" && Number.isInteger(e.path_index)).map((e) => e.path_index));
  const segments = [];
  let current = { points: [], times: [] };
  (track.path || []).forEach((sample, i) => {
    if (!Array.isArray(sample) || sample.length < 3) return;
    if (breaks.has(i) && current.points.length) {
      segments.push(current);
      current = { points: [], times: [] };
    }
    current.points.push([Number(sample[1]), Number(sample[2])]);
    current.times.push(Number(sample[0]));
  });
  if (current.points.length) segments.push(current);
  const lastT = Math.max(segments.at(-1)?.times.at(-1) || 0, events.at(-1)?.t || 0);
  return { segments, events, duration: Math.max(track.duration_s || 0, lastT) };
}

/** World area to show: the map and the whole route. */
function worldRect(map, segments) {
  const rect = mapRect(map);
  const xs = segments.flatMap((s) => s.points.map((p) => p[0]));
  const ys = segments.flatMap((s) => s.points.map((p) => p[1]));
  if (!xs.length) return rect || { x: 0, y: 0, w: 1, h: 1 };
  const path = { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) };
  if (!rect) return { x: path.x - PATH_ONLY_MARGIN, y: path.y - PATH_ONLY_MARGIN, w: path.w + PATH_ONLY_MARGIN * 2, h: path.h + PATH_ONLY_MARGIN * 2 };
  const x = Math.min(rect.x, path.x);
  const y = Math.min(rect.y, path.y);
  return { x, y, w: Math.max(rect.x + rect.w, path.x + path.w) - x, h: Math.max(rect.y + rect.h, path.y + path.h) - y };
}

/** How many points of a segment have time <= t. */
function pointsUntil(segment, t) {
  let count = 0;
  while (count < segment.times.length && segment.times[count] <= t) count += 1;
  return count;
}

function segmentAt(replay, t) {
  let index = replay.segments.length ? 0 : -1;
  replay.segments.forEach((segment, i) => {
    if (segment.times[0] <= t) index = i;
  });
  return index;
}

/** Player position at time t, interpolated between the two samples around it. */
function positionAt(replay, t) {
  const index = segmentAt(replay, t);
  if (index < 0) return null;
  const { points, times } = replay.segments[index];
  const count = pointsUntil(replay.segments[index], t);
  if (count <= 0) return points[0];
  if (count >= points.length) return points.at(-1);
  const [t0, t1] = [times[count - 1], times[count]];
  const k = t1 <= t0 ? 0 : Math.min(Math.max((t - t0) / (t1 - t0), 0), 1);
  const [a, b] = [points[count - 1], points[count]];
  return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k];
}

// --- Icons (RouteMapView.draw_event_icon) ------------------------------------------

/** Draws the icon of an event type (or "start") centered at x, y. */
export function drawEventIcon(ctx, type, x, y, size, sprites, event = {}) {
  const r = size / 2;
  ctx.save();
  switch (type) {
    case "death": {
      const sy = y - r * 0.15;
      const jaw = [x - r * 0.45, y + r * 0.25, r * 0.9, r * 0.55];
      ctx.fillStyle = OUTLINE;
      ctx.beginPath(); ctx.arc(x, sy, r * 0.8 + 1.5, 0, Math.PI * 2); ctx.fill();
      ctx.fillRect(jaw[0] - 1.5, jaw[1] - 1.5, jaw[2] + 3, jaw[3] + 3);
      ctx.fillStyle = BONE;
      ctx.beginPath(); ctx.arc(x, sy, r * 0.8, 0, Math.PI * 2); ctx.fill();
      ctx.fillRect(...jaw);
      ctx.fillStyle = OUTLINE;
      for (const dx of [-0.32, 0.32]) {
        ctx.beginPath(); ctx.arc(x + r * dx, sy + r * 0.05, r * 0.22, 0, Math.PI * 2); ctx.fill();
      }
      ctx.fillRect(x - 0.5, jaw[1], 1, jaw[3]);
      break;
    }
    case "damage": {
      const d = r * 0.7;
      ctx.lineCap = "round";
      for (const [width, color] of [[4.5, OUTLINE], [2.5, DAMAGE]]) {
        ctx.strokeStyle = color;
        ctx.lineWidth = width;
        ctx.beginPath();
        ctx.moveTo(x - d, y - d); ctx.lineTo(x + d, y + d);
        ctx.moveTo(x - d, y + d); ctx.lineTo(x + d, y - d);
        ctx.stroke();
      }
      break;
    }
    case "key":
      ctx.globalAlpha = event.faded ? 0.45 : 1;
      ctx.drawImage(sprites.key, x - r, y - r, size, size);
      break;
    case "heart":
      ctx.drawImage(sprites.heart, x - 9, y - 8, 18, 16);
      break;
    case "door": {
      const rect = [x - r * 0.7, y - r, r * 1.4, size];
      const border = event.state === "escaped" ? REVIVE : event.state === "locked" ? LOCKED : OUTLINE;
      ctx.fillStyle = border;
      ctx.fillRect(rect[0] - 1.5, rect[1] - 1.5, rect[2] + 3, rect[3] + 3);
      ctx.fillStyle = DOOR;
      ctx.fillRect(...rect);
      ctx.strokeStyle = "rgb(98, 59, 27)";
      ctx.lineWidth = 1;
      ctx.strokeRect(rect[0] + r * 0.25, rect[1] + r * 0.25, rect[2] - r * 0.5, rect[3] - r * 0.5);
      ctx.fillStyle = "rgb(255, 217, 77)";
      ctx.beginPath(); ctx.arc(rect[0] + rect[2] - r * 0.35, y + r * 0.1, Math.max(r * 0.12, 1), 0, Math.PI * 2); ctx.fill();
      break;
    }
    case "enemy_killed": {
      const d = r * 0.6;
      ctx.beginPath();
      ctx.moveTo(x, y - d); ctx.lineTo(x + d, y); ctx.lineTo(x, y + d); ctx.lineTo(x - d, y); ctx.closePath();
      ctx.fillStyle = KILL; ctx.fill();
      ctx.strokeStyle = OUTLINE; ctx.lineWidth = 1; ctx.stroke();
      break;
    }
    case "weapon_changed":
      ctx.fillStyle = OUTLINE;
      ctx.beginPath(); ctx.arc(x, y, r * 0.55 + 1, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = WEAPON;
      ctx.beginPath(); ctx.arc(x, y, r * 0.55, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = OUTLINE; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(x - r * 0.3, y + r * 0.3); ctx.lineTo(x + r * 0.3, y - r * 0.3); ctx.stroke();
      break;
    case "revive":
      for (const [width, color] of [[4, OUTLINE], [2, REVIVE]]) {
        ctx.strokeStyle = color; ctx.lineWidth = width;
        ctx.beginPath(); ctx.arc(x, y, r * 0.7, 0, Math.PI * 2); ctx.stroke();
      }
      ctx.strokeStyle = REVIVE; ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(x, y - r * 0.35); ctx.lineTo(x, y + r * 0.35);
      ctx.moveTo(x - r * 0.35, y); ctx.lineTo(x + r * 0.35, y);
      ctx.stroke();
      break;
    case "start":
      ctx.fillStyle = OUTLINE;
      ctx.beginPath(); ctx.arc(x, y, r * 0.6 + 1.5, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = START;
      ctx.beginPath(); ctx.arc(x, y, r * 0.6, 0, Math.PI * 2); ctx.fill();
      break;
    default:
      break;
  }
  ctx.restore();
}

/** A small canvas with one icon, for legends. */
export function iconCanvas(type, sprites, event = {}) {
  const size = 20;
  const dpr = window.devicePixelRatio || 1;
  const canvas = h("canvas", { width: size * dpr, height: size * dpr, style: `width: ${size}px; height: ${size}px`, "aria-hidden": "true" });
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);
  drawEventIcon(ctx, type, size / 2, size / 2, ICON, sprites, event);
  return canvas;
}

export function routeLegend(sprites) {
  const item = (type, text, event) => h("li", {}, iconCanvas(type, sprites, event), text);
  const stops = ROUTE_GRADIENT.map((_, i) => routeColor(i / (ROUTE_GRADIENT.length - 1))).join(", ");
  return h("ul", { class: "legend" },
    h("li", {}, h("span", { class: "gradient", style: `background: linear-gradient(90deg, ${stops})` }), "recorrido: inicio → final"),
    item("start", "inicio"),
    item("door", "puerta (verde: escapó; naranja: sin llave)", { state: "escaped" }),
    item("key", "llave"),
    item("death", "muerte"),
    item("damage", "daño"),
    item("enemy_killed", "enemigo eliminado"),
    item("heart", "corazón"),
    item("weapon_changed", "cambio de arma"),
    item("revive", "reaparición"));
}

// --- Event descriptions ------------------------------------------------------------

function eventText(event) {
  switch (event.type) {
    case "damage": return `-${formatHearts(event.amount ?? 1)} · ${sourceLabel(event.source)}`;
    case "death": return `por ${sourceLabel(event.cause)}${event.final === false ? " (reaparece)" : ""}`;
    case "enemy_killed": return ENEMY_LABELS[event.enemy] || event.enemy || "";
    case "heart": return `+${heartsText(event.amount ?? 1)}`;
    case "weapon_changed": return WEAPON_LABELS[event.weapon] || event.weapon || "";
    case "revive": return event.lives === undefined ? "? corazones" : heartsText(event.lives);
    case "door": return event.state === "escaped" ? "escapó" : event.state === "locked" ? "cerrada, sin llave" : "";
    default: return "";
  }
}

// --- Side panel ----------------------------------------------------------------------

function sourceList(items, emptyText) {
  if (!items.length) return h("p", { class: "muted", style: "margin: 0" }, emptyText);
  return h("ul", {}, items.map((item) => h("li", {}, sourceIcon(item.source, 1), item.label, h("span", { class: "count" }, item.count))));
}

function sidePanel(track) {
  const s = track.summary || {};
  const damage = (s.damage_by_source || []).reduce((sum, item) => sum + item.count, 0);
  const accuracy = s.attacks ? `${s.hits}/${s.attacks} (${Math.round((s.hits / s.attacks) * 100)} %)` : "—";
  return h("div", { class: "side" },
    h("div", { class: "side-box" },
      h("h4", {}, track.label),
      h("dl", {},
        h("dt", {}, "Resultado"), h("dd", {}, outcomeBadge(track.outcome)),
        h("dt", {}, "Tiempo"), h("dd", {}, formatDuration(track.duration_s)),
        h("dt", {}, "Intento"), h("dd", {}, track.attempt),
        h("dt", {}, "Dificultad planificada"), h("dd", {}, track.difficulty_index ?? "—"),
        h("dt", {}, "Versión del juego"), h("dd", {}, track.game_version || "—"))),
    h("div", { class: "side-box" },
      h("h4", {}, `Daño recibido (${damage})`),
      sourceList(s.damage_by_source || [], "Sin daño.")),
    h("div", { class: "side-box" },
      h("h4", {}, "Muertes"),
      sourceList(s.deaths_by_cause || [], "Sin muertes.")),
    h("div", { class: "side-box" },
      h("h4", {}, "Combate"),
      h("dl", {},
        h("dt", {}, "Enemigos eliminados"), h("dd", {}, s.kills ?? 0),
        h("dt", {}, "Golpes acertados"), h("dd", {}, accuracy),
        h("dt", {}, "Corazones"), h("dd", {}, s.hearts ?? 0),
        h("dt", {}, "Llave"), h("dd", {}, s.keys ? icon("key", 2, "sí") : "no"))),
    track.weapons_used?.length
      ? h("div", { class: "side-box" }, h("h4", {}, "Armas"), weaponIcons(track.weapons_used, 32),
        h("p", { class: "muted", style: "margin: 4px 0 0" }, track.weapons_used.map((id) => WEAPON_LABELS[id] || id).join(", ")))
      : null);
}

// --- The replay ------------------------------------------------------------------------

/** The map of one level with its route, controls, legend and summary. */
export function routeReplay(track, sprites) {
  const replay = buildReplay(track);
  const map = track.map || {};
  const image = mapRect(map) ? mapImage(map, sprites.tileset) : null;
  const world = worldRect(map, replay.segments);
  let time = replay.duration;
  let playing = false;
  let hits = [];

  const frame = h("div", { class: "map-frame" });
  const slider = h("input", { type: "range", min: 0, max: replay.duration.toFixed(2), step: 0.01, value: replay.duration.toFixed(2), "aria-label": "Tiempo del nivel" });
  const clock = h("output", {});
  const play = h("button", { class: "btn small", type: "button" }, "Reproducir");

  const heightFor = (width) => {
    const ratio = world.h / Math.max(world.w, 1);
    return Math.min(Math.max(width * ratio + MARGIN * 2, 200), Math.max(window.innerHeight * 0.7, 320));
  };

  const view = hiDpiCanvas(frame, heightFor, (ctx, width, height) => {
    ctx.fillStyle = BACKGROUND;
    ctx.fillRect(0, 0, width, height);
    const xf = fit(world, width, height, MARGIN);
    const toScreen = ([x, y]) => [xf.ox + x * xf.scale, xf.oy + y * xf.scale];
    drawMap(ctx, image, map, xf);
    hits = [];
    const seen = replay.events.filter((e) => (e.t || 0) <= time);
    drawMarkers(ctx, toScreen, seen);
    drawRoute(ctx, toScreen);
    for (const type of DRAWN_EVENTS) {
      for (const event of seen) {
        if (event.type !== type) continue;
        const [x, y] = toScreen([event.x || 0, event.y || 0]);
        drawEventIcon(ctx, type, x, y, ICON, sprites, event);
        hits.push({ x, y, event });
      }
    }
    // At the end the whole route is drawn and the head would cover the last
    // event (often the death), so it only shows while replaying.
    const head = time < replay.duration ? positionAt(replay, time) : null;
    if (head) {
      const [x, y] = toScreen(head);
      ctx.fillStyle = OUTLINE;
      ctx.beginPath(); ctx.arc(x, y, 6, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#fff";
      ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
    }
    if (!replay.segments.length) {
      ctx.fillStyle = "rgba(242, 224, 179, 0.85)";
      ctx.font = "20px 'Dungeon Body', sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("Sin recorrido registrado", width / 2, height / 2);
    }
  });

  function drawMarkers(ctx, toScreen, seen) {
    if (map.start) {
      const [x, y] = toScreen(cellCenter(map, map.start));
      drawEventIcon(ctx, "start", x, y, ICON * 0.8, sprites);
    }
    if (map.door) {
      const doorEvents = seen.filter((e) => e.type === "door");
      const state = doorEvents.at(-1)?.state || "";
      // The stored cell is the one below the door: the icon goes half a cell up.
      const [cx, cy] = cellCenter(map, map.door);
      const [x, y] = toScreen([cx, cy - (map.cell_px || 16) * 0.5]);
      drawEventIcon(ctx, "door", x, y, ICON * 1.2, sprites, { state });
      hits.push({ x, y, event: doorEvents.at(-1) || { type: "door", t: null } });
    }
    if (map.key && !seen.some((e) => e.type === "key")) {
      const [x, y] = toScreen(cellCenter(map, map.key));
      drawEventIcon(ctx, "key", x, y, ICON, sprites, { faded: true });
    }
  }

  function drawRoute(ctx, toScreen) {
    const duration = Math.max(replay.duration, 0.001);
    const current = segmentAt(replay, time);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.lineWidth = 3;
    replay.segments.forEach((segment, i) => {
      const points = segment.points.map(toScreen);
      if (points.length >= 2) {
        ctx.strokeStyle = GHOST;
        ctx.beginPath();
        points.forEach(([x, y], k) => (k ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
        ctx.stroke();
      }
      if (i > current) return;
      const count = pointsUntil(segment, time);
      const shown = points.slice(0, count);
      const times = segment.times.slice(0, count);
      if (i === current && count > 0 && count < points.length) {
        shown.push(toScreen(positionAt(replay, time)));
        times.push(time);
      }
      for (let k = 1; k < shown.length; k += 1) {
        ctx.strokeStyle = routeColor(times[k] / duration);
        ctx.beginPath();
        ctx.moveTo(...shown[k - 1]);
        ctx.lineTo(...shown[k]);
        ctx.stroke();
      }
    });
  }

  function setTime(value) {
    time = Math.min(Math.max(value, 0), replay.duration);
    slider.value = time.toFixed(2);
    clock.value = `${formatDuration(time)} / ${formatDuration(replay.duration)}`;
    view.redraw();
  }

  function stop() {
    playing = false;
    play.textContent = "Reproducir";
  }

  function tick(last) {
    return (now) => {
      if (!playing || !view.canvas.isConnected) return stop();
      const speed = replay.duration / PLAY_SECONDS;
      setTime(time + ((now - last) / 1000) * speed);
      if (time >= replay.duration) return stop();
      requestAnimationFrame(tick(now));
    };
  }

  play.addEventListener("click", () => {
    if (playing) return stop();
    if (time >= replay.duration) setTime(0);
    playing = true;
    play.textContent = "Pausa";
    requestAnimationFrame((now) => requestAnimationFrame(tick(now)));
  });
  slider.addEventListener("input", () => {
    stop();
    setTime(Number(slider.value));
  });
  view.canvas.addEventListener("mousemove", (event) => {
    const rect = view.canvas.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    let best = null;
    for (const hit of hits) {
      const d = Math.hypot(hit.x - x, hit.y - y);
      if (d <= HIT_RADIUS && (!best || d < best.d)) best = { ...hit, d };
    }
    if (!best) return hideTooltip();
    const e = best.event;
    showTooltip(event, h("strong", {}, EVENT_LABELS[e.type] || e.type),
      e.t !== null && e.t !== undefined ? ` · ${formatDuration(e.t)}` : "",
      eventText(e) ? [h("br"), eventText(e)] : null);
  });
  view.canvas.addEventListener("mouseleave", hideTooltip);
  setTime(time);

  return h("div", { class: "replay" },
    h("div", {},
      frame,
      h("div", { class: "replay-controls" }, play, slider, clock),
      routeLegend(sprites)),
    sidePanel(track));
}
