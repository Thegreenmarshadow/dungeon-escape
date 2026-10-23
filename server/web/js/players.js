// Players: who played the most (totals per player) and each player's profile.

import { columnChart } from "./charts.js";
import {
  api, avatar, badge, cards, emptyState, fill, formatAgo, formatDate, formatDuration, formatNumber, h,
  meter, modeBadge, outcomeBadge, playerCell, sortableTable, table, td,
} from "./dom.js";
import { MODE_LABELS } from "./labels.js";
import { openRunOnClick, runColumns } from "./runs.js";
import { hrefTo, setParams } from "./state.js";

function openProfileOnClick(totals, tr) {
  tr.classList.add("clickable");
  tr.addEventListener("click", (event) => {
    if (!event.target.closest("a, button")) location.hash = hrefTo("jugador", totals.player_id);
  });
}

export async function renderPlayers({ body, params, player, stale }) {
  const totals = await api("/api/players/totals", { mode: params.get("mode"), player });
  if (stale()) return;
  if (totals.length === 0) {
    body.replaceChildren(emptyState("No hay jugadores con partidas en este modo."));
    return;
  }
  const sum = (key) => totals.reduce((total, row) => total + row[key], 0);
  const maxTime = Math.max(...totals.map((t) => t.total_time_s));
  const maxScore = Math.max(...totals.map((t) => t.total_score));
  const mostActive = totals.reduce((best, row) => (row.total_time_s > best.total_time_s ? row : best));
  const columns = [
    { key: "player_name", label: "Jugador", cell: (t) => playerCell(t.player_name, t.player_id) },
    { key: "runs", label: "Partidas", num: true, cell: (t) => t.runs },
    {
      key: "total_score", label: "Puntos sumados", num: true,
      cell: (t) => [formatNumber(t.total_score), meter(t.total_score, maxScore, "gold")],
    },
    {
      key: "total_time_s", label: "Tiempo total", num: true,
      cell: (t) => [formatDuration(t.total_time_s), meter(t.total_time_s, maxTime)],
    },
    { key: "best_score", label: "Mejor puntaje", num: true, cell: (t) => formatNumber(t.best_score) },
    { key: "deepest_level", label: "Nivel máx.", num: true, cell: (t) => t.deepest_level },
    { key: "deaths", label: "Muertes", num: true, cell: (t) => t.deaths },
    {
      key: "last_played_at", label: "Última partida",
      cell: (t) => h("span", { title: formatDate(t.last_played_at) }, formatAgo(t.last_played_at)),
    },
  ];
  fill(body,
    cards([
      [avatar(mostActive.player_name), mostActive.player_name, "Juega más tiempo"],
      ["skull", formatNumber(sum("runs")), "Partidas"],
      ["torch", formatDuration(sum("total_time_s")), "Tiempo jugado"],
      ["orb", formatNumber(sum("total_score")), "Puntos sumados"],
    ]),
    h("p", { class: "muted" }, "Clic en un jugador para ver su perfil, o en un encabezado para ordenar."),
    sortableTable(columns, totals, { sort: "total_time_s", dir: "desc", row: openProfileOnClick }),
  );
}

// --- Profile ---------------------------------------------------------------------

function modeTable(byMode) {
  const rows = Object.entries(byMode).map(([mode, t]) => h("tr", {},
    td(modeBadge(mode)),
    td(t.runs, "num"),
    td(formatNumber(t.total_score), "num"),
    td(formatDuration(t.total_time_s), "num"),
    td(formatNumber(t.best_score), "num"),
    td(t.deepest_level, "num"),
    td(t.deaths, "num"),
  ));
  return table(
    [["Modo"], ["Partidas", "num"], ["Puntos", "num"], ["Tiempo", "num"], ["Mejor", "num"],
      ["Nivel máx.", "num"], ["Muertes", "num"]],
    rows,
    "Sin partidas.",
  );
}

const OUTCOME_COLORS = { died: "var(--danger)", quit: "var(--warn)", in_progress: "var(--ok)" };

/** Score of every run, oldest first; the color is how it ended. */
function scoreChart(runs) {
  const ordered = [...runs].reverse();
  return columnChart(ordered, {
    value: (r) => r.score,
    color: (r) => OUTCOME_COLORS[r.outcome] || "var(--gold)",
    format: (v) => formatNumber(v),
    label: (r) => new Date(r.started_at).toLocaleDateString("es", { day: "numeric", month: "numeric" }),
    tooltip: (r) => [
      h("strong", {}, `${formatNumber(r.score)} puntos`),
      h("br"),
      `${formatDate(r.started_at)} · nivel ${r.level_reached}`,
      h("br"),
      `${MODE_LABELS[r.mode] || r.mode} · `, outcomeBadge(r.outcome),
    ],
    onClick: (r) => { location.hash = hrefTo("partida", r.id); },
  });
}

function legend() {
  return h("ul", { class: "legend" },
    [["var(--danger)", "Murió"], ["var(--warn)", "Abandonó"], ["var(--ok)", "En curso"]].map(([color, text]) =>
      h("li", {}, h("span", { class: "swatch", style: `width: 12px; height: 12px; background: ${color}` }), text)));
}

export async function renderProfile({ arg, body, player, stale }) {
  const profile = await api(`/api/players/${encodeURIComponent(arg)}`);
  if (stale()) return;
  const { player: who, totals, totals_by_mode: byMode, best_run: best, runs } = profile;
  const filtered = player.toLowerCase() === who.name.toLowerCase();
  const filterAction = filtered
    ? badge("Filtro activo en todas las secciones", "completed")
    : h("button", { class: "btn", type: "button", onclick: () => setParams({ player: who.name }, { push: true }) },
      `Filtrar todo por ${who.name}`);
  const bestValue = best ? h("a", { href: hrefTo("partida", best.id) }, formatNumber(best.score)) : "—";
  fill(body,
    h("a", { class: "back", href: hrefTo("jugadores") }, "« Todos los jugadores"),
    h("div", { class: "panel moss" },
      h("h2", { class: "panel-title" }, "Perfil"),
      h("div", { class: "profile-head" },
        avatar(who.name, true),
        h("div", { class: "who" },
          h("h2", {}, who.name),
          h("p", { class: "muted" },
            totals.runs
              ? `Jugando desde ${formatDate(profile.first_played_at)} · última partida ${formatAgo(totals.last_played_at)}`
              : "Todavía no jugó ninguna partida.")),
        filterAction),
      cards([
        ["skull", totals.runs, "Partidas"],
        ["orb", formatNumber(totals.total_score), "Puntos sumados"],
        ["torch", formatDuration(totals.total_time_s), "Tiempo total"],
        ["coin", bestValue, best ? `Mejor partida · nivel ${best.level_reached}` : "Mejor partida (modo normal)"],
        ["reaper", totals.deepest_level, "Nivel máximo"],
        ["bones", totals.deaths, "Muertes"],
        ["candle", formatAgo(totals.last_played_at), "Última partida"],
      ]),
      Object.keys(byMode).length ? [h("h3", {}, "Por modo"), modeTable(byMode)] : null),
    runs.length
      ? h("div", { class: "panel" },
        h("h2", { class: "panel-title" }, "Puntaje por partida"),
        h("p", { class: "muted" }, "De la más vieja a la más nueva. Clic en una barra para abrir la partida."),
        scoreChart(runs),
        legend())
      : null,
    h("div", { class: "panel" },
      h("h2", { class: "panel-title" }, `Partidas de ${who.name}`),
      runs.length
        ? sortableTable(runColumns({ withPlayer: false }), runs, { sort: "started_at", dir: "desc", row: openRunOnClick })
        : emptyState("Todavía no hay partidas.")),
  );
}
