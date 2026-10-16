"use strict";

// Hash routes: #/ranking, #/partidas, #/partida/<id>, #/estadisticas.

const EVENT_LABELS = {
  level_started: "Nivel iniciado",
  level_completed: "Nivel superado",
  enemy_killed: "Enemigo eliminado",
  damage_taken: "Daño recibido",
  heart_picked: "Corazón recogido",
  key_picked: "Llave recogida",
  player_died: "Muerte",
  run_quit: "Partida abandonada",
};

const ENEMY_LABELS = {
  Skeleton: "Esqueleto",
  Vampire: "Vampiro",
  Skull: "Calavera",
  Reaper: "Parca",
};

const OUTCOME_LABELS = { died: "Murió", quit: "Abandonó", in_progress: "En curso" };
const MODE_LABELS = { normal: "Normal", test: "Prueba" };

// --- Helpers ----------------------------------------------------------------

/** Builds an element. Text children are inserted as text, never as HTML. */
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") el.className = value;
    else el.setAttribute(key, value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined) continue;
    el.append(child instanceof Node ? child : String(child));
  }
  return el;
}

async function api(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText} (${path})`);
  return response.json();
}

function showError(error) {
  const box = document.getElementById("error");
  box.textContent = error ? `No se pudieron cargar los datos: ${error.message}` : "";
  box.hidden = !error;
}

function formatDuration(seconds) {
  const total = Math.round(seconds || 0);
  const m = Math.floor(total / 60);
  const s = String(total % 60).padStart(2, "0");
  return `${m}:${s}`;
}

function formatDate(iso) {
  if (!iso) return "—";
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : date.toLocaleString("es");
}

function badge(text, kind) {
  return h("span", { class: `badge ${kind || ""}` }, text);
}

function table(headers, rows, emptyText) {
  if (rows.length === 0) return h("div", { class: "table-wrap" }, h("p", { class: "empty" }, emptyText));
  const head = h("tr", {}, headers.map(([label, cls]) => h("th", { class: cls }, label)));
  return h("div", { class: "table-wrap" },
    h("table", {}, h("thead", {}, head), h("tbody", {}, rows)));
}

function td(content, cls) {
  return h("td", { class: cls }, content);
}

function runLink(run) {
  return h("a", { href: `#/partida/${encodeURIComponent(run.id || run.run_id)}` }, "Ver");
}

// --- Sections ---------------------------------------------------------------

async function renderRanking() {
  const board = await api("/api/leaderboard?limit=20");
  const rows = board.entries.map((e) => h("tr", {},
    td(`#${e.rank}`),
    td(e.player_name),
    td(e.score, "num"),
    td(e.level_reached, "num"),
    td(e.enemies_killed, "num"),
    td(formatDuration(e.duration_s), "num"),
    td(formatDate(e.ended_at)),
    td(runLink(e)),
  ));
  const body = document.getElementById("ranking-body");
  body.replaceChildren(
    board.best_level > 0 ? h("p", {}, `Nivel máximo alcanzado: ${board.best_level}`) : "",
    table(
      [["#"], ["Jugador"], ["Puntos", "num"], ["Nivel", "num"], ["Enemigos", "num"],
        ["Duración", "num"], ["Fecha"], [""]],
      rows,
      "Todavía no hay partidas terminadas.",
    ),
  );
}

async function loadPlayerOptions() {
  const select = document.querySelector("#runs-filter select[name=player]");
  const current = select.value;
  const players = await api("/api/players");
  select.replaceChildren(h("option", { value: "" }, "Todos"),
    players.map((p) => h("option", { value: p.name }, p.name)));
  select.value = players.some((p) => p.name === current) ? current : "";
}

async function renderRuns() {
  await loadPlayerOptions();
  const form = new FormData(document.getElementById("runs-filter"));
  const params = new URLSearchParams();
  for (const [key, value] of form) if (value) params.set(key, value);
  const runs = await api(`/api/runs?${params}`);
  const rows = runs.map((r) => h("tr", {},
    td(formatDate(r.started_at)),
    td(r.player_name),
    td(badge(MODE_LABELS[r.mode] || r.mode)),
    td(badge(OUTCOME_LABELS[r.outcome] || r.outcome, r.outcome)),
    td(r.score, "num"),
    td(r.level_reached, "num"),
    td(r.enemies_killed, "num"),
    td(formatDuration(r.duration_s), "num"),
    td(runLink(r)),
  ));
  document.getElementById("runs-body").replaceChildren(table(
    [["Inicio"], ["Jugador"], ["Modo"], ["Resultado"], ["Puntos", "num"], ["Nivel", "num"],
      ["Enemigos", "num"], ["Duración", "num"], [""]],
    rows,
    "No hay partidas con estos filtros.",
  ));
}

function eventDetail(event) {
  const p = event.payload || {};
  switch (event.type) {
    case "enemy_killed": return ENEMY_LABELS[p.enemy] || p.enemy || "";
    case "damage_taken": return `-${p.amount ?? 1} · quedan ${p.lives ?? "?"} vidas`;
    case "heart_picked": return `+${p.amount ?? 1} · ${p.lives ?? "?"} vidas`;
    case "level_started": return `${p.enemies_total ?? "?"} enemigos · ${p.lives ?? "?"} vidas`;
    case "level_completed":
      return `en ${formatDuration(p.duration_s)} · ${p.kills ?? "?"}/${p.enemies_total ?? "?"} enemigos`;
    case "player_died":
    case "run_quit":
      return p.score !== undefined ? `${p.score} puntos` : "";
    default:
      return Object.keys(p).length ? JSON.stringify(p) : "";
  }
}

async function renderRun(runId) {
  const run = await api(`/api/runs/${encodeURIComponent(runId)}`);
  const summary = [
    ["Puntos", run.score],
    ["Nivel alcanzado", run.level_reached],
    ["Enemigos eliminados", run.enemies_killed],
    ["Duración", formatDuration(run.duration_s)],
  ].map(([label, value]) => h("div", { class: "card" },
    h("div", { class: "value" }, value), h("div", { class: "label" }, label)));
  const timeline = run.events.length === 0
    ? h("p", { class: "empty" }, "Esta partida no tiene eventos.")
    : h("ol", { class: "timeline" }, run.events.map((e) => h("li", {},
      h("span", { class: "time" }, formatDuration(e.t_run_s)),
      h("strong", {}, EVENT_LABELS[e.type] || e.type),
      e.level ? ` · nivel ${e.level}` : "",
      eventDetail(e) ? h("span", { class: "detail" }, ` · ${eventDetail(e)}`) : "",
    )));
  document.getElementById("run-body").replaceChildren(
    h("h2", {}, `Partida de ${run.player_name}`),
    h("p", { class: "muted" },
      badge(MODE_LABELS[run.mode] || run.mode), " ",
      badge(OUTCOME_LABELS[run.outcome] || run.outcome, run.outcome),
      ` · inicio ${formatDate(run.started_at)} · fin ${formatDate(run.ended_at)}`,
      ` · nivel inicial ${run.start_level} · semilla ${run.run_seed}`),
    h("div", { class: "cards" }, summary),
    h("h3", {}, `Eventos (${run.events.length})`),
    timeline,
  );
}

async function renderStats() {
  const mode = new FormData(document.getElementById("stats-filter")).get("mode");
  const stats = await api(`/api/stats${mode ? `?mode=${mode}` : ""}`);
  const cards = [
    ["Partidas", stats.total_runs],
    ["Terminadas", stats.finished_runs],
    ["Jugadores", stats.total_players],
    ["Enemigos eliminados", stats.total_kills],
    ["Llaves recogidas", stats.keys_collected],
    ["Corazones recogidos", stats.hearts_collected],
    ["Daño recibido", stats.damage_taken],
    ["Niveles superados", stats.levels_completed],
    ["Duración promedio", formatDuration(stats.avg_duration_s)],
    ["Nivel máximo", stats.best_level],
    ["Mejor puntaje", stats.best_score],
  ].map(([label, value]) => h("div", { class: "card" },
    h("div", { class: "value" }, value), h("div", { class: "label" }, label)));
  const rows = Object.entries(stats.events_by_type).map(([type, count]) => h("tr", {},
    td(EVENT_LABELS[type] || type), td(type, "muted"), td(count, "num")));
  document.getElementById("stats-body").replaceChildren(
    h("div", { class: "cards" }, cards),
    h("h3", {}, "Eventos por tipo"),
    table([["Evento"], ["Tipo"], ["Cantidad", "num"]], rows, "Todavía no hay eventos."),
  );
}

// --- Router -----------------------------------------------------------------

async function route() {
  const [, section = "ranking", arg] = location.hash.split("/");
  const id = section === "partida" ? "partida" : section;
  for (const el of document.querySelectorAll("main > section")) el.hidden = el.id !== id;
  for (const link of document.querySelectorAll("nav a")) {
    const active = link.dataset.section === id || (id === "partida" && link.dataset.section === "partidas");
    link.classList.toggle("active", active);
  }
  showError(null);
  try {
    if (id === "partidas") await renderRuns();
    else if (id === "partida") await renderRun(decodeURIComponent(arg || ""));
    else if (id === "estadisticas") await renderStats();
    else {
      document.getElementById("ranking").hidden = false;
      await renderRanking();
    }
  } catch (error) {
    showError(error);
  }
}

document.getElementById("runs-filter").addEventListener("change", () => renderRuns().catch(showError));
document.getElementById("stats-filter").addEventListener("change", () => renderStats().catch(showError));
window.addEventListener("hashchange", route);
route();
