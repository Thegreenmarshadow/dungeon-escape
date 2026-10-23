// Analytics of the uploaded level telemetry (/api/analytics), like the game's
// AnalyticsReport and DifficultyReport: warnings, heatmaps per map, planned vs
// measured difficulty, per-level stats and what hurts and kills the players.

import { hbars, responsive, svg } from "./charts.js";
import {
  api, emptyState, fill, formatDuration, formatHearts, formatNumber, formatPercent, h, hideTooltip, icon, meter,
  showTooltip, sortableTable, sourceIcon, weaponIcons,
} from "./dom.js";
import { sourceLabel } from "./labels.js";
import { drawMap, hiDpiCanvas, loadSprites, mapImage } from "./map-canvas.js";
import { setParams } from "./state.js";

const LAYERS = [
  { id: "time", label: "Tiempo", unit: (v) => `${v.toFixed(1)} s`, total: (v) => formatDuration(v) },
  { id: "damage", label: "Daño recibido", unit: (v) => `${formatHearts(v)} corazones de daño`, total: (v) => formatHearts(v) },
  { id: "deaths", label: "Muertes", unit: (v) => `${Math.round(v)} muertes`, total: (v) => formatNumber(v) },
];
// HeatmapView's colors, from little to a lot (translucent over the floor). The
// game report uses this scale, so the page keeps it to read the same way.
const HEAT_GRADIENT = [[0.25, 0.45, 1.0, 0.55], [1.0, 0.85, 0.2, 0.8], [1.0, 0.15, 0.1, 0.95]];
const MARKERS = [
  ["start", "I", "rgb(89, 230, 115)"],
  ["key", "L", "rgb(255, 217, 51)"],
  ["door", "P", "rgb(140, 191, 255)"],
];

function heatColor(fraction) {
  const f = Math.min(Math.max(fraction, 0), 1) * (HEAT_GRADIENT.length - 1);
  const i = Math.min(Math.floor(f), HEAT_GRADIENT.length - 2);
  const k = f - i;
  const c = HEAT_GRADIENT[i].map((v, j) => v + (HEAT_GRADIENT[i + 1][j] - v) * k);
  return `rgba(${Math.round(c[0] * 255)}, ${Math.round(c[1] * 255)}, ${Math.round(c[2] * 255)}, ${c[3].toFixed(2)})`;
}

// --- Filters -----------------------------------------------------------------------

/** Fills the level and version filters with the values that exist. */
function fillOptions(section, options, params) {
  const fillSelect = (name, values, allText, label = (v) => v) => {
    const select = section.querySelector(`select[name=${name}]`);
    if (!select) return;
    fill(select, h("option", { value: "" }, allText), values.map((v) => h("option", { value: String(v) }, label(v))));
    const value = params.get(name) || "";
    select.value = values.map(String).includes(value) ? value : "";
  };
  fillSelect("level", options.levels || [], "Todos", (v) => `Nivel ${v}`);
  fillSelect("version", options.versions || [], "Todas", (v) => v || "(sin versión)");
}

// --- Warnings --------------------------------------------------------------------------

function insightIcon(line) {
  if (line.includes("muere")) return icon("bones", 2);
  if (line.includes("abandona")) return icon("flag", 2);
  if (line.includes("daño")) return icon("spikes", 2);
  if (line.includes("tiempo")) return icon("candle", 2);
  return icon("torch", 2);
}

function insightsList(lines, minAttempts) {
  if (lines.length === 0) {
    return h("ul", { class: "insights" }, h("li", { class: "note" }, icon("torch", 2),
      `Sin avisos: ningún nivel supera los umbrales (con al menos ${minAttempts} intentos).`));
  }
  return h("ul", { class: "insights" }, lines.map((line) => {
    const note = line.startsWith("Sin avisos");
    return h("li", { class: note ? "note" : null }, note ? icon("torch", 2) : insightIcon(line), line);
  }));
}

// --- Heatmaps ------------------------------------------------------------------------------

function heatmapPanel(groups, sprites, params) {
  if (groups.length === 0) return emptyState("No hay recorridos con estos filtros.");
  let group = groups.find((g) => g.key === params.get("map")) || groups[0];
  // A map chosen before changing the filters may be gone: forget it.
  if (params.get("map") && group.key !== params.get("map")) setParams({ map: "" }, { silent: true });
  let layer = LAYERS.find((l) => l.id === params.get("layer")) || LAYERS[0];
  let image = null;
  let values = new Map();
  let max = 0;
  let hovered = null;
  let geometry = null;

  const mapSelect = h("select", { "aria-label": "Mapa" }, groups.map((g) => h("option", { value: g.key },
    `${g.label} · ${g.attempts} ${g.attempts === 1 ? "intento" : "intentos"}`)));
  const layerButtons = h("div", { class: "layers", role: "group", "aria-label": "Capa" });
  const readout = h("p", { class: "heat-readout" });
  const legend = h("div", { class: "legend" });
  const frame = h("div", { class: "map-frame" });

  const view = hiDpiCanvas(frame, (width) => {
    const [w, hgt] = group.map.size;
    return Math.min(Math.max(width * (hgt / Math.max(w, 1)), 180), Math.max(window.innerHeight * 0.65, 300));
  }, (ctx, width, height) => {
    ctx.fillStyle = "#0a0609";
    ctx.fillRect(0, 0, width, height);
    const [w, hgt] = group.map.size;
    const cell = Math.max(Math.min(width / w, height / hgt), 0.5);
    const ox = Math.floor((width - w * cell) / 2);
    const oy = Math.floor((height - hgt * cell) / 2);
    geometry = { cell, ox, oy, w, h: hgt };
    const size = group.map.cell_px || 16;
    const [mx, my] = group.map.origin || [0, 0];
    drawMap(ctx, image, group.map, { scale: cell / size, ox: ox - (mx * cell) / size, oy: oy - (my * cell) / size });
    // Darker floor so the heat stands out, like the report's dim floor.
    ctx.fillStyle = "rgba(10, 6, 9, 0.45)";
    ctx.fillRect(ox, oy, w * cell, hgt * cell);
    if (max > 0) {
      for (const [index, value] of values) {
        ctx.fillStyle = heatColor(Math.sqrt(value / max));
        ctx.fillRect(ox + (index % w) * cell, oy + Math.floor(index / w) * cell, Math.ceil(cell), Math.ceil(cell));
      }
    }
    ctx.font = "bold 14px 'Dungeon Body', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (const [key, letter, color] of MARKERS) {
      const at = group.map[key];
      if (!at) continue;
      const cx = ox + (at[0] + 0.5) * cell;
      const cy = oy + (at[1] + 0.5) * cell;
      const radius = Math.max(cell * 0.9, 8);
      ctx.fillStyle = "rgba(0, 0, 0, 0.65)";
      ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = color; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = color;
      ctx.fillText(letter, cx, cy + 1);
    }
    if (hovered) {
      ctx.strokeStyle = "rgba(255, 255, 255, 0.9)";
      ctx.lineWidth = 1;
      ctx.strokeRect(ox + hovered[0] * cell + 0.5, oy + hovered[1] * cell + 0.5, cell - 1, cell - 1);
    }
  });

  function describeHover() {
    if (!hovered) {
      readout.textContent = max > 0
        ? `${group.label}: ${group.attempts} intentos. Pasá el mouse por el mapa para ver el valor de cada celda.`
        : "Esta capa no tiene valores en este mapa.";
      return;
    }
    const value = values.get(hovered[1] * geometry.w + hovered[0]) || 0;
    readout.textContent = `Celda (${hovered[0]}, ${hovered[1]}): ${layer.unit(value)}`;
  }

  function update() {
    values = new Map(group.layers[layer.id] || []);
    max = Math.max(0, ...values.values());
    fill(layerButtons, LAYERS.map((l) => h("button", {
      class: `btn small${l.id === layer.id ? " active" : ""}`,
      type: "button",
      "aria-pressed": String(l.id === layer.id),
      onclick: () => {
        layer = l;
        setParams({ layer: l.id === LAYERS[0].id ? "" : l.id }, { silent: true });
        update();
      },
    }, `${l.label} · ${l.total(group.totals[l.id] || 0)}`)));
    const stops = [0, 0.25, 0.5, 0.75, 1].map(heatColor).join(", ");
    fill(legend,
      h("span", {}, "0"),
      h("span", { class: "gradient", style: `width: 120px; background: linear-gradient(90deg, ${stops})` }),
      h("span", {}, max > 0 ? layer.unit(max) : "sin valores"),
      h("span", { class: "muted" }, "· I inicio · L llave · P puerta · escala en raíz cuadrada"));
    describeHover();
    view.redraw();
  }

  function selectGroup(key) {
    group = groups.find((g) => g.key === key) || groups[0];
    image = mapImage(group.map, sprites.tileset);
    hovered = null;
    mapSelect.value = group.key;
    setParams({ map: group === groups[0] ? "" : group.key }, { silent: true });
    update();
    // Another map can have another shape.
    view.resize();
  }

  mapSelect.addEventListener("change", () => selectGroup(mapSelect.value));
  view.canvas.addEventListener("mousemove", (event) => {
    if (!geometry) return;
    const rect = view.canvas.getBoundingClientRect();
    const x = Math.floor((event.clientX - rect.left - geometry.ox) / geometry.cell);
    const y = Math.floor((event.clientY - rect.top - geometry.oy) / geometry.cell);
    const inside = x >= 0 && y >= 0 && x < geometry.w && y < geometry.h;
    const next = inside ? [x, y] : null;
    if (String(next) === String(hovered)) return;
    hovered = next;
    describeHover();
    view.redraw();
  });
  view.canvas.addEventListener("mouseleave", () => {
    hovered = null;
    describeHover();
    view.redraw();
  });

  image = mapImage(group.map, sprites.tileset);
  mapSelect.value = group.key;
  update();
  return h("div", {},
    h("div", { class: "heat-controls" },
      h("label", { class: "filters" }, h("span", { class: "visually-hidden" }, "Mapa"), mapSelect),
      layerButtons),
    frame,
    readout,
    legend);
}

// --- Difficulty chart ---------------------------------------------------------------------

/** Planned (dashed blue) vs measured (solid orange) difficulty per level, like
 * the game's difficulty_chart.gd: gaps where a level has no value and hollow
 * points with fewer than minAttempts attempts. */
function difficultyChart(points, minAttempts) {
  const series = [
    { key: "planned", label: "planificada", color: "var(--planned)", dash: "6 4" },
    { key: "measured", label: "medida", color: "var(--measured)", dash: null },
  ];
  const chart = responsive((width) => {
    const height = 240;
    const pad = { left: 40, right: 90, top: 14, bottom: 30 };
    const plotW = Math.max(width - pad.left - pad.right, 40);
    const plotH = height - pad.top - pad.bottom;
    const n = points.length;
    const x = (i) => pad.left + (n > 1 ? (i / (n - 1)) * plotW : plotW / 2);
    const y = (v) => pad.top + plotH - v * plotH;
    const every = Math.max(1, Math.ceil(n / Math.max(Math.floor(plotW / 36), 1)));
    const crosshair = svg("line", { class: "axis", x1: 0, x2: 0, y1: pad.top, y2: pad.top + plotH, visibility: "hidden", "stroke-dasharray": "2 3" });

    const lines = series.map((s) => {
      const parts = [];
      let current = [];
      points.forEach((p, i) => {
        if (p[s.key] === null || p[s.key] === undefined) {
          if (current.length) parts.push(current);
          current = [];
        } else current.push([x(i), y(p[s.key])]);
      });
      if (current.length) parts.push(current);
      return svg("g", {},
        parts.map((part) => svg("polyline", {
          points: part.map((pt) => pt.join(",")).join(" "), fill: "none", stroke: s.color, "stroke-width": 2,
          "stroke-dasharray": s.dash, "stroke-linejoin": "round",
        })),
        points.map((p, i) => (p[s.key] === null || p[s.key] === undefined ? null : svg("circle", {
          cx: x(i), cy: y(p[s.key]), r: 4, stroke: s.color, "stroke-width": 2,
          fill: s.key === "measured" && p.attempts < minAttempts ? "var(--panel)" : s.color,
        }))));
    });
    // Direct labels at the end of each line, pushed apart when they would overlap.
    const ends = series.map((s) => {
      const index = points.findLastIndex((p) => p[s.key] !== null && p[s.key] !== undefined);
      return index < 0 ? null : { s, x: x(index) + 8, y: y(points[index][s.key]) + 4 };
    });
    if (ends[0] && ends[1] && Math.abs(ends[0].y - ends[1].y) < 16) {
      const middle = (ends[0].y + ends[1].y) / 2;
      const [upper, lower] = ends[0].y <= ends[1].y ? ends : [ends[1], ends[0]];
      upper.y = middle - 8;
      lower.y = middle + 8;
      upper.x = lower.x = Math.max(upper.x, lower.x);
    }
    const lastLabel = (end) => (end
      ? svg("text", { x: end.x, y: end.y, "font-size": 14, class: "label-strong" }, end.s.label)
      : null);
    const slot = plotW / Math.max(n - 1, 1);
    return svg("svg", { class: "chart", width, height, viewBox: `0 0 ${width} ${height}`, role: "img", "aria-label": "Dificultad planificada y medida por nivel" },
      [0, 0.5, 1].map((tick) => [
        svg("line", { class: tick ? "grid" : "axis", x1: pad.left, x2: pad.left + plotW, y1: y(tick), y2: y(tick) }),
        svg("text", { x: pad.left - 8, y: y(tick) + 4, "text-anchor": "end", "font-size": 13 }, tick.toFixed(1)),
      ]),
      points.map((p, i) => (i % every === 0
        ? svg("text", { x: x(i), y: height - 10, "text-anchor": "middle", "font-size": 13 }, p.level) : null)),
      crosshair,
      lines,
      ends.map(lastLabel),
      points.map((p, i) => svg("rect", {
        x: x(i) - slot / 2, y: pad.top, width: slot, height: plotH, fill: "transparent",
        onmousemove: (event) => {
          crosshair.setAttribute("x1", x(i));
          crosshair.setAttribute("x2", x(i));
          crosshair.setAttribute("visibility", "visible");
          showTooltip(event, h("strong", {}, `Nivel ${p.level}`), h("br"),
            `planificada: ${p.planned === null ? "—" : p.planned.toFixed(2)}`, h("br"),
            `medida: ${p.measured === null ? "—" : p.measured.toFixed(2)}`, h("br"),
            `${p.attempts} intentos${p.attempts && p.attempts < minAttempts ? " (pocos datos)" : ""}`);
        },
        onmouseleave: () => {
          crosshair.setAttribute("visibility", "hidden");
          hideTooltip();
        },
      })));
  });
  const legendItem = (s) => h("li", {},
    svg("svg", { width: 28, height: 10, "aria-hidden": "true" },
      svg("line", { x1: 0, x2: 28, y1: 5, y2: 5, stroke: s.color, "stroke-width": 2, "stroke-dasharray": s.dash })),
    `Dificultad ${s.label}`);
  const hollow = svg("svg", { width: 12, height: 12, "aria-hidden": "true" },
    svg("circle", { cx: 6, cy: 6, r: 4, fill: "var(--panel)", stroke: "var(--measured)", "stroke-width": 2 }));
  return h("div", {}, chart,
    h("ul", { class: "legend" }, series.map(legendItem), h("li", {}, hollow, `menos de ${minAttempts} intentos`)));
}

// --- Per-level table ------------------------------------------------------------------------

function levelTable(rows, labels, minAttempts) {
  const few = (r) => r.attempts < minAttempts;
  const columns = [
    { key: "level", label: "Nivel", num: true, cell: (r) => `Nivel ${r.level}` },
    {
      key: "attempts", label: "Intentos", num: true,
      cell: (r) => (few(r) ? h("span", { class: "muted", title: "Pocos intentos: dato poco fiable" }, `${r.attempts}*`) : r.attempts),
    },
    { key: "completion_rate", label: "Superan", num: true, cell: (r) => formatPercent(r.completion_rate) },
    { key: "death_rate", label: "Mueren", num: true, cell: (r) => formatPercent(r.death_rate) },
    { key: "abandon_rate", label: "Abandonan", num: true, cell: (r) => formatPercent(r.abandon_rate) },
    { key: "mean_time_s", label: "Tiempo medio", num: true, cell: (r) => formatDuration(r.mean_time_s) },
    { key: "damage_per_min", label: "Daño/min", num: true, cell: (r) => formatNumber(r.damage_per_min, 1) },
    { key: "deaths_per_attempt", label: "Muertes/intento", num: true, cell: (r) => formatNumber(r.deaths_per_attempt, 2) },
    {
      key: "top_death_cause", label: "Causa principal",
      value: (r) => r.top_death_share,
      cell: (r) => (r.top_death_cause
        ? h("span", { class: "chip" }, sourceIcon(r.top_death_cause, 1), labels[r.top_death_cause] || sourceLabel(r.top_death_cause),
          h("span", { class: "muted" }, ` · ${formatPercent(r.top_death_share)}`))
        : h("span", { class: "muted" }, "—")),
    },
    {
      key: "measured_difficulty", label: "Dificultad medida", num: true,
      cell: (r) => [formatNumber(r.measured_difficulty, 2), meter(r.measured_difficulty, 1)],
    },
    { key: "weapons", label: "Armas", value: false, cell: (r) => weaponIcons(r.weapons_used, 16) },
  ];
  return sortableTable(columns, rows, { sort: "level", dir: "asc", empty: "No hay niveles terminados con estos filtros." });
}

/** Totals of a {source: count} field over every level row, most first. */
function sumBySource(rows, field, labels) {
  const totals = {};
  for (const row of rows) {
    for (const [source, count] of Object.entries(row[field] || {})) totals[source] = (totals[source] || 0) + count;
  }
  return Object.entries(totals).sort((a, b) => b[1] - a[1]).map(([source, value]) => {
    const label = labels[source] || sourceLabel(source);
    return { name: [sourceIcon(source, 1), label], title: label, value, text: formatNumber(value) };
  });
}

// --- Section --------------------------------------------------------------------------------

export async function renderAnalytics({ body, params, player, stale }) {
  const [data, sprites] = await Promise.all([
    api("/api/analytics", { player, level: params.get("level"), version: params.get("version"), mode: params.get("mode") }),
    loadSprites(),
  ]);
  if (stale()) return;
  fillOptions(document.getElementById("analitica"), data.options, params);
  const minAttempts = data.thresholds?.min_attempts ?? 5;
  if (data.files === 0) {
    fill(body, h("div", { class: "panel" }, h("h2", { class: "panel-title" }, "Analítica"),
      emptyState("Todavía no hay telemetría de niveles con estos filtros.")));
    return;
  }
  const labels = data.source_labels || {};
  const attempts = data.levels.reduce((sum, row) => sum + row.attempts, 0);
  fill(body,
    h("div", { class: "panel lava" },
      h("h2", { class: "panel-title" }, "Avisos"),
      h("p", { class: "muted" },
        `${formatNumber(data.files)} archivos de nivel · ${formatNumber(attempts)} intentos en ${data.levels.length} niveles`,
        player ? ` · solo ${player}` : "",
        ". Reglas del juego: muertes ≥ 40 %, abandonos ≥ 40 %, tiempo ≥ 2,5× o daño ≥ 2× el nivel anterior."),
      insightsList(data.insights, minAttempts)),
    h("div", { class: "panel ice" },
      h("h2", { class: "panel-title" }, "Mapas de calor"),
      h("p", { class: "muted" }, "Partidas jugadas sobre el mismo mapa, una encima de otra: dónde pasan el tiempo, dónde reciben daño y dónde mueren."),
      heatmapPanel(data.heatmaps, sprites, params)),
    h("div", { class: "panel" },
      h("h2", { class: "panel-title" }, "Dificultad por nivel"),
      h("p", { class: "muted" }, "Planificada: el índice del generador dividido por su máximo. Medida: 50 % muertes por intento + 50 % daño por minuto, relativa al nivel más difícil (vale 1). Si la naranja sube más que la azul, el nivel es más difícil de lo planeado."),
      difficultyChart(data.chart, minAttempts)),
    h("div", { class: "panel" },
      h("h2", { class: "panel-title" }, "Estadísticas por nivel"),
      levelTable(data.levels, labels, minAttempts),
      h("p", { class: "muted" }, `* Menos de ${minAttempts} intentos: dato poco fiable. La demo queda afuera salvo con el modo Demo.`)),
    h("div", { class: "grid-2" },
      h("div", { class: "panel" },
        h("h2", { class: "panel-title" }, "Causas de muerte"),
        hbars(sumBySource(data.levels, "deaths_by_cause", labels), { empty: "Nadie murió con estos filtros." })),
      h("div", { class: "panel" },
        h("h2", { class: "panel-title" }, "Daño por fuente"),
        hbars(sumBySource(data.levels, "damage_by_source", labels), { kind: "damage", empty: "Sin daño con estos filtros." }))),
  );
}
