// Small SVG and HTML charts in the style of the game's reports
// (bar_chart_view.gd, difficulty_chart.gd). Each one redraws at the width of
// its container and shows the exact values on hover.

import { h, hideTooltip, showTooltip } from "./dom.js";

const NS = "http://www.w3.org/2000/svg";

/** Builds an SVG element; text children become text nodes. */
export function svg(tag, attrs = {}, ...children) {
  const el = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key.startsWith("on") && typeof value === "function") el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value);
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

/** A box that calls draw(width) now and again whenever its width changes. */
export function responsive(draw, className = "chart-box") {
  const box = h("div", { class: className });
  let lastWidth = 0;
  const render = (width) => {
    if (width <= 0 || Math.abs(width - lastWidth) < 1) return;
    lastWidth = width;
    box.replaceChildren(draw(Math.floor(width)));
  };
  // Drawing in the next frame keeps the observer from reacting to its own redraw.
  new ResizeObserver((entries) => {
    const width = entries[0].contentRect.width;
    requestAnimationFrame(() => render(width));
  }).observe(box);
  return box;
}

/** A round axis maximum (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a
 * power of ten) at least value. */
export function niceMax(value) {
  if (!(value > 0)) return 1;
  const power = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
    if (value <= step * power) return step * power;
  }
  return 10 * power;
}

function hoverHandlers(content, onClick) {
  return {
    onmousemove: (event) => showTooltip(event, content()),
    onmouseleave: hideTooltip,
    onclick: onClick || null,
    style: onClick ? "cursor: pointer" : null,
  };
}

/**
 * Vertical bars, one per item, in order.
 * options: { value(item), color(item), tooltip(item) -> nodes, onClick(item),
 *            label(item) -> short text under some bars, height, format(value) }
 */
export function columnChart(items, options) {
  const { value, tooltip, onClick, label, height = 180, format = String, color = () => "var(--gold)" } = options;
  return responsive((width) => {
    const pad = { left: 44, right: 8, top: 12, bottom: label ? 26 : 10 };
    const plotW = Math.max(width - pad.left - pad.right, 10);
    const plotH = height - pad.top - pad.bottom;
    const max = niceMax(Math.max(...items.map(value), 0));
    const y = (v) => pad.top + plotH - (v / max) * plotH;
    const slot = plotW / Math.max(items.length, 1);
    const barW = Math.max(Math.min(slot * 0.7, 32), 2);
    const every = Math.max(1, Math.ceil(items.length / Math.max(Math.floor(plotW / 60), 1)));
    const ticks = [0, max / 2, max];
    return svg("svg", { class: "chart", width, height, viewBox: `0 0 ${width} ${height}`, role: "img" },
      ticks.map((tick) => [
        svg("line", { class: tick ? "grid" : "axis", x1: pad.left, x2: width - pad.right, y1: y(tick), y2: y(tick) }),
        svg("text", { x: pad.left - 6, y: y(tick) + 4, "text-anchor": "end", "font-size": 13 }, format(tick)),
      ]),
      items.map((item, i) => {
        const v = value(item);
        const x = pad.left + slot * i + (slot - barW) / 2;
        return svg("g", hoverHandlers(() => tooltip(item), onClick && (() => onClick(item))),
          svg("rect", { x: pad.left + slot * i, y: pad.top, width: slot, height: plotH, fill: "transparent" }),
          svg("rect", { x, y: y(v), width: barW, height: Math.max(y(0) - y(v), v > 0 ? 1 : 0), fill: color(item) }),
          label && i % every === 0
            ? svg("text", { x: x + barW / 2, y: height - 8, "text-anchor": "middle", "font-size": 13 }, label(item))
            : null);
      }));
  });
}

/**
 * Horizontal bars as an HTML list (labels stay readable on phones).
 * rows: [{ name: text or nodes, title: text (for the tooltip), value, text?: shown value }]
 */
export function hbars(rows, { kind = "", empty = "Sin datos." } = {}) {
  if (rows.length === 0) return h("p", { class: "empty" }, empty);
  const max = Math.max(...rows.map((r) => r.value), 0);
  const total = rows.reduce((sum, r) => sum + r.value, 0);
  return h("ul", { class: "hbars" }, rows.map((r) => h("li", {
    onmousemove: (event) => showTooltip(event, h("strong", {}, r.title), ` · ${r.text ?? r.value}`),
    onmouseleave: hideTooltip,
  },
  h("span", { class: "name" }, r.name),
  h("span", { class: "track" }, h("span", { class: `fill ${kind}`, style: `width: ${max ? ((r.value / max) * 100).toFixed(1) : 0}%` })),
  h("span", { class: "value" }, r.text ?? r.value, total ? h("span", { class: "muted" }, ` · ${Math.round((r.value / total) * 100)} %`) : null))));
}
