// Router and global player filter. Each section module renders into its
// <section id="..."> from the state in the URL (see state.js).

import { renderAnalytics } from "./analytics.js";
import { api, avatar, fill, formatDuration, formatNumber, h, hideTooltip } from "./dom.js";
import { renderPlayers, renderProfile } from "./players.js";
import { renderRanking } from "./ranking.js";
import { renderRun, renderRuns } from "./runs.js";
import { DEFAULT_SECTION, currentRoute, hrefTo, setParams } from "./state.js";
import { renderStats } from "./stats.js";

const SECTIONS = {
  ranking: { title: "Ranking", render: renderRanking },
  jugadores: { title: "Jugadores", render: renderPlayers },
  jugador: { title: "Perfil", render: renderProfile, nav: "jugadores" },
  partidas: { title: "Partidas", render: renderRuns },
  partida: { title: "Partida", render: renderRun, nav: "partidas" },
  analitica: { title: "Analítica", render: renderAnalytics },
  estadisticas: { title: "Estadísticas", render: renderStats },
};

let renderToken = 0;
let previousView = "";

function showError(error) {
  const box = document.getElementById("error");
  if (error?.status === 404) box.textContent = "No existe: ese jugador o esa partida no está en la base de datos.";
  else box.textContent = error ? `No se pudieron cargar los datos: ${error.message}` : "";
  box.hidden = !error;
}

/** Fills the global filter with every player, keeping the chosen one. */
async function loadPlayers(selected) {
  const select = document.getElementById("player-filter");
  const players = await api("/api/players");
  const match = players.find((p) => p.name.toLowerCase() === selected.toLowerCase());
  fill(select,
    h("option", { value: "" }, "Todos"),
    players.map((p) => h("option", { value: p.name }, p.name)),
    selected && !match ? h("option", { value: selected }, selected) : null);
  select.value = match ? match.name : selected;
}

function stat(value, label) {
  return h("span", { class: "stat" }, h("strong", {}, value), " ", label);
}

/** Totals of the filtered player under the navigation. */
async function renderFilterStrip(ctx) {
  const strip = document.getElementById("filter-strip");
  if (!ctx.player) {
    strip.hidden = true;
    strip.replaceChildren();
    return;
  }
  const [totals] = await api("/api/players/totals", { player: ctx.player });
  if (ctx.stale()) return;
  const clear = h("button", { class: "btn small", type: "button", onclick: () => setParams({ player: "" }, { push: true }) },
    "Quitar filtro ✕");
  const profile = totals && h("a", { class: "btn small", href: hrefTo("jugador", totals.player_id) }, "Ver perfil");
  fill(strip,
    h("span", { class: "who" }, avatar(totals?.player_name || ctx.player), `Filtro: ${totals?.player_name || ctx.player}`),
    totals
      ? [
        stat(totals.runs, totals.runs === 1 ? "partida" : "partidas"),
        stat(formatNumber(totals.total_score), "puntos"),
        stat(formatDuration(totals.total_time_s), "jugado"),
        stat(formatNumber(totals.best_score), "mejor puntaje"),
        stat(totals.deepest_level, "nivel máximo"),
        stat(totals.deaths, totals.deaths === 1 ? "muerte" : "muertes"),
      ]
      : h("span", { class: "muted" }, "No tiene partidas registradas."),
    h("span", { class: "actions" }, profile, clear));
  strip.hidden = false;
}

/** Shows each filter of the section as the URL says. */
function syncFilters(section, params) {
  for (const select of section.querySelectorAll("form[data-filters] select")) {
    const value = params.get(select.name) || "";
    select.value = [...select.options].some((option) => option.value === value) ? value : "";
  }
}

async function route() {
  const token = ++renderToken;
  const { section, arg, params } = currentRoute();
  const id = SECTIONS[section] ? section : DEFAULT_SECTION;
  const entry = SECTIONS[id];
  const navId = entry.nav || id;
  for (const el of document.querySelectorAll("main > section")) el.hidden = el.id !== id;
  for (const link of document.querySelectorAll("nav a")) {
    link.href = hrefTo(link.dataset.section);
    const active = link.dataset.section === navId;
    link.classList.toggle("active", active);
    if (active) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  document.querySelector(".brand").href = hrefTo(DEFAULT_SECTION);
  document.title = `${entry.title} · Dungeon Escape`;

  const sectionEl = document.getElementById(id);
  const body = document.getElementById(`${id}-body`);
  syncFilters(sectionEl, params);
  showError(null);
  hideTooltip();
  const view = `${id}/${arg}`;
  if (view !== previousView) {
    body.replaceChildren(h("p", { class: "loading" }, "Cargando…"));
    if (previousView) window.scrollTo(0, 0);
    previousView = view;
  }

  const player = params.get("player") || "";
  const ctx = { arg, params, player, body, stale: () => token !== renderToken };
  const results = await Promise.allSettled([loadPlayers(player), renderFilterStrip(ctx), entry.render(ctx)]);
  const failed = results.find((result) => result.status === "rejected");
  if (failed && !ctx.stale()) {
    showError(failed.reason);
    if (body.querySelector(".loading")) body.replaceChildren();
  }
}

document.getElementById("player-filter").addEventListener("change", (event) => {
  setParams({ player: event.target.value }, { push: true });
});
for (const form of document.querySelectorAll("form[data-filters]")) {
  form.addEventListener("change", (event) => {
    if (event.target.name) setParams({ [event.target.name]: event.target.value });
  });
  form.addEventListener("submit", (event) => event.preventDefault());
}
window.addEventListener("hashchange", route);
route();
