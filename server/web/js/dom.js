// Shared helpers: building elements, fetching JSON, formatting and tables.

import { MODE_LABELS, OUTCOME_LABELS, SOURCE_ICONS, WEAPON_LABELS, sourceLabel } from "./labels.js";
import { hrefTo } from "./state.js";

/**
 * Builds an element. Text children are inserted as text, never as HTML.
 * Attributes named on<event> with a function value become event listeners.
 */
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") el.className = value;
    else if (key.startsWith("on") && typeof value === "function") el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value === true ? "" : value);
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : String(child));
  }
  return el;
}

/** Replaces the children of el; arrays are flattened and empty values skipped. */
export function fill(el, ...children) {
  el.replaceChildren(...children.flat(Infinity).filter((c) => c !== null && c !== undefined && c !== false));
  return el;
}

/** GET a JSON endpoint. Empty parameters are left out of the query. */
export async function api(path, params = {}) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") query.set(key, value);
  }
  const url = query.size ? `${path}?${query}` : path;
  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText} (${url})`);
  return response.json();
}

// --- Formatting -------------------------------------------------------------

/** "m:ss", or "h:mm:ss" from one hour up. */
export function formatDuration(seconds) {
  const total = Math.round(seconds || 0);
  const hours = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, "0");
  return hours ? `${hours}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

export function formatNumber(value, digits = 0) {
  return Number(value || 0).toLocaleString("es", { maximumFractionDigits: digits, minimumFractionDigits: digits });
}

/** 0.48 -> "48 %", like the game's reports. */
export function formatPercent(rate) {
  return `${Math.round((rate || 0) * 100)} %`;
}

export function formatDate(iso) {
  if (!iso) return "—";
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : date.toLocaleString("es", { dateStyle: "short", timeStyle: "short" });
}

const RELATIVE = new Intl.RelativeTimeFormat("es", { numeric: "auto" });
const RELATIVE_STEPS = [["day", 86400], ["hour", 3600], ["minute", 60]];

/** "hace 3 días", "ayer", "hace 5 minutos". */
export function formatAgo(iso) {
  if (!iso) return "—";
  const seconds = (new Date(iso).getTime() - Date.now()) / 1000;
  if (Number.isNaN(seconds)) return iso;
  for (const [unit, size] of RELATIVE_STEPS) {
    if (Math.abs(seconds) >= size) return RELATIVE.format(Math.round(seconds / size), unit);
  }
  return RELATIVE.format(0, "minute");
}

// --- Pieces -------------------------------------------------------------------

// Natural size of the sprites in assets/icons that are not 16 x 16.
const ICON_SIZES = {
  skeleton: 24, vampire: 24, archer: 24, mage: 24, mimic: 24, "skull-turret": 24,
  forge: 24, lich: 24, warden: 24, heart: [9, 8],
};

/** A sprite from assets/icons drawn at a whole multiple (scale) of its size. */
export function icon(name, scale = 2, label = "") {
  const natural = ICON_SIZES[name] || 16;
  const [w, h_] = Array.isArray(natural) ? natural : [natural, natural];
  const width = w * scale;
  const height = h_ * scale;
  return h("img", {
    class: "px-icon",
    src: `assets/icons/${name}.png`,
    width,
    height,
    alt: label,
    title: label || null,
    loading: "lazy",
  });
}

export function sourceIcon(source, scale = 1) {
  return icon(SOURCE_ICONS[source] || SOURCE_ICONS.unknown, scale, sourceLabel(source));
}

export function weaponIcons(ids, size = 32) {
  return h("span", { class: "weapons" }, (ids || []).map((id) => h("img", {
    class: "px-icon",
    src: `assets/weapons/${encodeURIComponent(id)}.png`,
    width: size,
    height: size,
    alt: WEAPON_LABELS[id] || id,
    title: WEAPON_LABELS[id] || id,
    onerror: (event) => event.target.replaceWith(h("span", { class: "muted" }, WEAPON_LABELS[id] || id)),
  })));
}

// Dungeon_Character.png: 7 heroes on the first row and 7 monsters on the second.
const AVATAR_COUNT = 14;
const AVATAR_COLUMNS = 7;

/** The same game character for the same player name, everywhere. */
export function avatar(name, big = false) {
  let hash = 0;
  for (const char of String(name).toLowerCase()) hash = (hash * 31 + char.codePointAt(0)) >>> 0;
  const index = hash % AVATAR_COUNT;
  const size = big ? 64 : 32;
  const x = (index % AVATAR_COLUMNS) * size;
  const y = Math.floor(index / AVATAR_COLUMNS) * size;
  return h("span", { class: `avatar${big ? " big" : ""}`, style: `background-position: -${x}px -${y}px`, "aria-hidden": "true" });
}

export function badge(text, kind) {
  return h("span", { class: `badge ${kind || ""}` }, text);
}

export function modeBadge(mode) {
  return badge(MODE_LABELS[mode] || mode, `mode-${mode}`);
}

export function outcomeBadge(outcome) {
  return badge(OUTCOME_LABELS[outcome] || outcome, outcome);
}

/** The pixel heart of the game (9 x 8), at 3x. */
export function heartIcon(label = "", scale = 3) {
  return icon("heart", scale, label);
}

/** A player's character and name, linked to the profile when the id is known. */
export function playerCell(name, id) {
  if (id === undefined || id === null) return h("span", { class: "who-cell" }, avatar(name), name);
  return h("a", { class: "who-cell", href: hrefTo("jugador", id) }, avatar(name), name);
}

/** Stat tiles: [[icon name or element, value, label], ...]. */
export function cards(items) {
  return h("div", { class: "cards" }, items.map(([iconName, value, label]) => h("div", { class: "card" },
    typeof iconName === "string" ? icon(iconName, 2) : iconName,
    h("div", { class: typeof value === "string" && /[a-zñáéíóú]/i.test(value) ? "value text" : "value" }, value),
    h("div", { class: "label" }, label),
  )));
}

export function emptyState(text) {
  return h("div", { class: "empty-state" },
    h("span", { class: "sprite skeleton", style: "background-image: url(assets/sprites/skeleton.png)", "aria-hidden": "true" }),
    h("p", { class: "empty" }, text));
}

/** A thin bar of value / max under a number. */
export function meter(value, max, kind = "") {
  const width = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  return h("span", { class: `meter ${kind}` }, h("span", { style: `width: ${width.toFixed(1)}%` }));
}

// --- Tooltip -------------------------------------------------------------------

const tooltipBox = () => document.getElementById("tooltip");

/** Shows the shared tooltip next to the pointer; content is text or nodes. */
export function showTooltip(event, ...content) {
  const box = tooltipBox();
  fill(box, content.flat(Infinity).map((c) => (c instanceof Node || c === null || c === false ? c : String(c))));
  box.hidden = false;
  const pad = 14;
  const { innerWidth, innerHeight } = window;
  const rect = box.getBoundingClientRect();
  let x = event.clientX + pad;
  let y = event.clientY + pad;
  if (x + rect.width > innerWidth - 4) x = event.clientX - rect.width - pad;
  if (y + rect.height > innerHeight - 4) y = event.clientY - rect.height - pad;
  box.style.left = `${Math.max(4, x)}px`;
  box.style.top = `${Math.max(4, y)}px`;
}

export function hideTooltip() {
  tooltipBox().hidden = true;
}

// --- Tables ------------------------------------------------------------------------

export function table(headers, rows, emptyText) {
  if (rows.length === 0) return h("div", { class: "table-wrap" }, h("p", { class: "empty" }, emptyText));
  const head = h("tr", {}, headers.map(([label, cls]) => h("th", { class: cls, scope: "col" }, label)));
  return h("div", { class: "table-wrap" }, h("table", {}, h("thead", {}, head), h("tbody", {}, rows)));
}

export function td(content, cls) {
  return h("td", { class: cls }, content);
}

function compare(a, b) {
  const aMissing = a === null || a === undefined || a === "";
  const bMissing = b === null || b === undefined || b === "";
  if (aMissing || bMissing) return aMissing === bMissing ? 0 : aMissing ? 1 : -1;
  if (typeof a === "number" && typeof b === "number") return a - b;
  return String(a).localeCompare(String(b), "es", { sensitivity: "base", numeric: true });
}

/**
 * A table sorted by clicking its headers.
 * columns: [{ key, label, cell(item) -> content, value?(item) -> sort value
 *             (false: not sortable), num?, cls? }]
 * options: { sort: key, dir: "asc" | "desc", empty: text, row(item, tr) }
 */
export function sortableTable(columns, items, { sort, dir = "desc", empty = "Sin datos.", row } = {}) {
  const wrap = h("div", { class: "table-wrap" });
  let sortKey = sort;
  let sortDir = dir;

  function render() {
    if (items.length === 0) {
      wrap.replaceChildren(h("p", { class: "empty" }, empty));
      return;
    }
    const column = columns.find((c) => c.key === sortKey);
    const valueOf = column && (column.value || ((item) => item[column.key]));
    const sorted = column
      ? [...items].sort((a, b) => compare(valueOf(a), valueOf(b)) * (sortDir === "asc" ? 1 : -1))
      : items;
    const head = h("tr", {}, columns.map((c) => {
      const cls = [c.num ? "num" : "", c.cls || ""].join(" ").trim() || null;
      if (c.value === false) return h("th", { class: cls, scope: "col" }, c.label);
      const state = c.key === sortKey ? (sortDir === "asc" ? "ascending" : "descending") : null;
      return h("th", { class: cls, scope: "col", "aria-sort": state },
        h("button", { class: "sort", type: "button", onclick: () => toggle(c) }, c.label));
    }));
    const body = sorted.map((item) => {
      const tr = h("tr", {}, columns.map((c) => td(c.cell(item), [c.num ? "num" : "", c.cls || ""].join(" ").trim() || null)));
      if (row) row(item, tr);
      return tr;
    });
    wrap.replaceChildren(h("table", {}, h("thead", {}, head), h("tbody", {}, body)));
  }

  function toggle(column) {
    if (column.key === sortKey) sortDir = sortDir === "asc" ? "desc" : "asc";
    else {
      sortKey = column.key;
      // Numbers start from the biggest, names from A.
      sortDir = column.num ? "desc" : "asc";
    }
    render();
    wrap.querySelector(`th[aria-sort] .sort`)?.focus();
  }

  render();
  return wrap;
}
