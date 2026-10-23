// Run history and the detail of one run.

import {
  api, avatar, cards, emptyState, formatDate, formatDuration, formatNumber, h, icon,
  modeBadge, outcomeBadge, playerCell, sortableTable,
} from "./dom.js";
import { ENEMY_LABELS, EVENT_LABELS, ITEM_LABELS, WEAPON_LABELS, sourceLabel } from "./labels.js";
import { hrefTo } from "./state.js";

/** Columns of a run list; the profile leaves the player out. */
export function runColumns({ withPlayer = true } = {}) {
  return [
    { key: "started_at", label: "Inicio", cell: (r) => formatDate(r.started_at) },
    withPlayer && { key: "player_name", label: "Jugador", cell: (r) => playerCell(r.player_name, r.player_id) },
    { key: "score", label: "Puntos", num: true, cls: "score", cell: (r) => formatNumber(r.score) },
    { key: "level_reached", label: "Nivel", num: true, cell: (r) => r.level_reached },
    { key: "outcome", label: "Resultado", cell: (r) => outcomeBadge(r.outcome) },
    { key: "mode", label: "Modo", cell: (r) => modeBadge(r.mode) },
    { key: "enemies_killed", label: "Enemigos", num: true, cell: (r) => r.enemies_killed },
    { key: "coins_collected", label: "Monedas", num: true, cell: (r) => r.coins_collected },
    { key: "coins_spent", label: "Gastadas", num: true, cell: (r) => r.coins_spent },
    { key: "duration_s", label: "Duración", num: true, cell: (r) => formatDuration(r.duration_s) },
    {
      key: "level_tracks",
      label: "Recorrido",
      num: true,
      cell: (r) => (r.level_tracks
        ? h("span", { class: "chip", title: `${r.level_tracks} niveles con recorrido` }, icon("flag", 1), r.level_tracks)
        : h("span", { class: "muted" }, "—")),
    },
    { key: "link", label: "", value: false, cell: (r) => h("a", { href: hrefTo("partida", r.id) }, "Ver") },
  ].filter(Boolean);
}

/** Makes the whole row open the run (links and buttons keep working). */
export function openRunOnClick(run, tr) {
  tr.classList.add("clickable");
  tr.addEventListener("click", (event) => {
    if (!event.target.closest("a, button")) location.hash = hrefTo("partida", run.id);
  });
}

export async function renderRuns({ body, params, player, stale }) {
  const runs = await api("/api/runs", { player, mode: params.get("mode"), limit: params.get("limit") });
  if (stale()) return;
  if (runs.length === 0) {
    body.replaceChildren(emptyState("No hay partidas con estos filtros."));
    return;
  }
  body.replaceChildren(
    h("p", { class: "muted" }, `${runs.length} partidas, de la más reciente a la más vieja. Clic en un encabezado para ordenar.`),
    sortableTable(runColumns({ withPlayer: !player }), runs, { sort: "started_at", dir: "desc", row: openRunOnClick }),
  );
}

// --- One run ---------------------------------------------------------------------

function eventDetail(event) {
  const p = event.payload || {};
  switch (event.type) {
    case "enemy_killed":
    case "enemy_dodged":
      return ENEMY_LABELS[p.enemy] || p.enemy || "";
    case "damage_taken": {
      const source = p.source ? ` · ${sourceLabel(p.source)}` : "";
      return `-${p.amount ?? 1} · quedan ${p.lives ?? "?"} vidas${source}`;
    }
    case "heart_picked": return `+${p.amount ?? 1} · ${p.lives ?? "?"} vidas`;
    case "coin_picked": return `+${p.amount ?? "?"}`;
    case "item_bought": return `${ITEM_LABELS[p.item] || p.item || "?"} · ${p.price ?? "?"} monedas`;
    case "level_started": return `${p.enemies_total ?? "?"} enemigos · ${p.lives ?? "?"} vidas`;
    case "level_completed":
      return `en ${formatDuration(p.duration_s)} · ${p.kills ?? "?"}/${p.enemies_total ?? "?"} enemigos`;
    case "weapon_changed": return WEAPON_LABELS[p.weapon] || p.weapon || "";
    case "player_respawned": return `${p.lives ?? "?"} vidas`;
    case "player_died": {
      const cause = p.cause ? ` · por ${sourceLabel(p.cause)}` : "";
      return p.score !== undefined ? `${p.score} puntos${cause}` : cause.slice(3);
    }
    case "run_quit":
      return p.score !== undefined ? `${p.score} puntos` : "";
    default:
      return Object.keys(p).length ? JSON.stringify(p) : "";
  }
}

function timeline(events) {
  if (events.length === 0) return h("p", { class: "empty" }, "Esta partida no tiene eventos.");
  return h("ol", { class: "timeline" }, events.map((e) => {
    const detail = eventDetail(e);
    return h("li", {},
      h("span", { class: "time" }, formatDuration(e.t_run_s)),
      h("strong", {}, EVENT_LABELS[e.type] || e.type),
      e.level ? ` · nivel ${e.level}` : "",
      detail ? h("span", { class: "detail" }, ` · ${detail}`) : "");
  }));
}

function runHeader(run) {
  return h("div", { class: "panel" },
    h("h2", { class: "panel-title" }, "Partida"),
    h("div", { class: "profile-head" },
      avatar(run.player_name, true),
      h("div", { class: "who" },
        h("h2", {}, `Partida de ${run.player_name}`),
        h("div", { class: "run-meta" },
          modeBadge(run.mode), outcomeBadge(run.outcome),
          h("span", {}, `inicio ${formatDate(run.started_at)} · fin ${formatDate(run.ended_at)}`),
          h("span", {}, `nivel inicial ${run.start_level} · semilla ${run.run_seed}`)))),
    cards([
      ["orb", formatNumber(run.score), "Puntos"],
      ["reaper", run.level_reached, "Nivel alcanzado"],
      ["skeleton", run.enemies_killed, "Enemigos eliminados"],
      ["coin", run.coins_collected, "Monedas recogidas"],
      ["chest", run.coins_spent, "Monedas gastadas"],
      ["torch", formatDuration(run.duration_s), "Duración"],
    ]));
}

function eventsPanel(events) {
  return h("div", { class: "panel" },
    h("h2", { class: "panel-title" }, "Eventos"),
    h("details", { open: events.length <= 40 },
      h("summary", {}, `${events.length} eventos de la partida`),
      timeline(events)));
}

export async function renderRun({ arg, body, stale }) {
  const run = await api(`/api/runs/${encodeURIComponent(arg)}`);
  if (stale()) return;
  body.replaceChildren(
    h("a", { class: "back", href: hrefTo("partidas") }, "« Volver al historial"),
    runHeader(run),
    eventsPanel(run.events),
  );
}
