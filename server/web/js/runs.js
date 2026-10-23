// Run history and the detail of one run.

import {
  api, avatar, cards, emptyState, fill, formatDate, formatDuration, formatHearts, formatNumber, h, heartIcon,
  heartsText, icon,
  modeBadge, outcomeBadge, playerCell, sortableTable, sourceIcon, table, td, weaponIcons,
} from "./dom.js";
import { ENEMY_LABELS, EVENT_LABELS, ITEM_LABELS, WEAPON_LABELS, sourceLabel } from "./labels.js";
import { loadSprites } from "./map-canvas.js";
import { routeReplay } from "./route-map.js";
import { hrefTo, setParams } from "./state.js";

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
      return `-${formatHearts(p.amount ?? 1)} · quedan ${p.lives === undefined ? "? corazones" : heartsText(p.lives)}${source}`;
    }
    case "heart_picked": return `+${formatHearts(p.amount ?? 1)} · ${p.lives === undefined ? "? corazones" : heartsText(p.lives)}`;
    case "coin_picked": return `+${p.amount ?? "?"}`;
    case "item_bought": return `${ITEM_LABELS[p.item] || p.item || "?"} · ${p.price ?? "?"} monedas`;
    case "level_started": return `${p.enemies_total ?? "?"} enemigos · ${p.lives === undefined ? "? corazones" : heartsText(p.lives)}`;
    case "level_completed":
      return `en ${formatDuration(p.duration_s)} · ${p.kills ?? "?"}/${p.enemies_total ?? "?"} enemigos`;
    case "weapon_changed": return WEAPON_LABELS[p.weapon] || p.weapon || "";
    case "player_respawned": return p.lives === undefined ? "? corazones" : heartsText(p.lives);
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
        h("h2", {}, "Partida de ", h("a", { href: hrefTo("jugador", run.player_id) }, run.player_name)),
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

// --- Per-level breakdown ---------------------------------------------------------

function counted(map) {
  return Object.entries(map)
    .map(([source, count]) => ({ source, label: sourceLabel(source), count }))
    .sort((a, b) => b.count - a.count || a.source.localeCompare(b.source));
}

/** What the run events (RunRecorder) say about each level. */
function eventLevels(events) {
  const levels = new Map();
  const get = (level) => {
    if (!levels.has(level)) {
      levels.set(level, {
        level, first: null, last: null, kills: 0, damage: 0, sources: {}, deaths: 0, causes: {},
        key: false, coins: 0, hearts: 0, outcome: "in_progress", duration: null, weapons: [], lastSource: "",
      });
    }
    return levels.get(level);
  };
  for (const e of events) {
    if (!e.level || e.type === "item_bought") continue;
    const row = get(e.level);
    const p = e.payload || {};
    row.first ??= e.t_run_s;
    row.last = e.t_run_s;
    switch (e.type) {
      case "enemy_killed": row.kills += 1; break;
      case "damage_taken": {
        const amount = Number(p.amount ?? 1);
        row.lastSource = p.source || "unknown";
        row.damage += amount;
        row.sources[row.lastSource] = (row.sources[row.lastSource] || 0) + amount;
        break;
      }
      case "player_died":
      case "player_respawned": {
        // The demo revives the player instead of ending the run: still a death.
        const cause = p.cause || row.lastSource || "unknown";
        row.deaths += 1;
        row.causes[cause] = (row.causes[cause] || 0) + 1;
        if (e.type === "player_died") row.outcome = "died";
        break;
      }
      case "key_picked": row.key = true; break;
      case "coin_picked": row.coins += Number(p.amount || 0); break;
      case "heart_picked": row.hearts += Number(p.amount ?? 1); break;
      case "level_completed": row.outcome = "completed"; row.duration = p.duration_s ?? null; break;
      case "run_quit": row.outcome = "abandoned"; break;
      case "weapon_changed": if (p.weapon && !row.weapons.includes(p.weapon)) row.weapons.push(p.weapon); break;
      default: break;
    }
  }
  for (const row of levels.values()) row.duration ??= Math.max((row.last ?? 0) - (row.first ?? 0), 0);
  return levels;
}

/** One row per level played: from the level files when the run has them
 * (one per attempt), otherwise from the run events. */
export function breakdownRows(run, tracks) {
  const byLevel = eventLevels(run.events || []);
  if (tracks.length) {
    const attempts = {};
    for (const t of tracks) attempts[t.level] = (attempts[t.level] || 0) + 1;
    return tracks.map((t, index) => {
      const s = t.summary || {};
      const sum = (items) => (items || []).reduce((total, item) => total + item.count, 0);
      const events = byLevel.get(t.level);
      return {
        label: shortLabel(t),
        title: t.label,
        attempt: t.attempt,
        outcome: t.outcome,
        duration: t.duration_s,
        damage: sum(s.damage_by_source),
        sources: s.damage_by_source || [],
        deaths: sum(s.deaths_by_cause),
        causes: s.deaths_by_cause || [],
        kills: s.kills ?? 0,
        key: (s.keys ?? 0) > 0,
        hearts: s.hearts ?? 0,
        hits: s.hits ?? 0,
        attacks: s.attacks ?? 0,
        // Coins come from the run events, which do not tell attempts apart.
        coins: attempts[t.level] === 1 && events ? events.coins : null,
        weapons: t.weapons_used || [],
        track: index,
      };
    });
  }
  return [...byLevel.values()].sort((a, b) => a.level - b.level).map((row) => ({
    label: `Nivel ${row.level}`,
    attempt: 1,
    outcome: row.outcome,
    duration: row.duration,
    damage: row.damage,
    sources: counted(row.sources),
    deaths: row.deaths,
    causes: counted(row.causes),
    kills: row.kills,
    key: row.key,
    hearts: row.hearts,
    hits: null,
    attacks: null,
    coins: row.coins,
    weapons: row.weapons,
    track: null,
  }));
}

/** "Nivel 2" or "Demo": the full label (with the level seed) is too long for
 * tabs and tables; it stays in the title and the replay's side panel. */
export function shortLabel(track) {
  return track.mode === "demo" ? "Demo" : `Nivel ${track.level}`;
}

function sourceChips(items, format = (count) => `${count}`) {
  return h("span", { class: "chips" }, items.map((item) => h("span", { class: "chip", title: item.label },
    sourceIcon(item.source, 1), format(item.count))));
}

function breakdownTable(rows, onSelect) {
  const dash = () => h("span", { class: "muted" }, "—");
  const trs = rows.map((row) => {
    const tr = h("tr", { "data-track": row.track ?? "" },
      td(h("span", { title: row.title || null }, row.label,
        row.attempt > 1 ? h("span", { class: "muted" }, ` · intento ${row.attempt}`) : "")),
      td(outcomeBadge(row.outcome)),
      td(formatDuration(row.duration), "num"),
      td(row.damage ? h("span", { class: "chips" }, h("strong", {}, formatHearts(row.damage)),
        sourceChips(row.sources, formatHearts)) : dash()),
      td(row.deaths ? h("span", { class: "chips" }, h("strong", {}, row.deaths), sourceChips(row.causes)) : dash()),
      td(row.kills, "num"),
      td(row.key ? icon("key", 2, "llave recogida") : dash()),
      td(row.hearts ? h("span", { class: "chip" }, heartIcon("", 2), formatHearts(row.hearts)) : dash()),
      td(row.attacks ? `${row.hits}/${row.attacks} · ${Math.round((row.hits / row.attacks) * 100)} %` : dash(), "num"),
      td(row.coins ?? dash(), "num"),
      td(row.weapons.length ? weaponIcons(row.weapons, 32) : dash()),
    );
    if (row.track !== null) {
      tr.classList.add("clickable");
      tr.title = "Ver su recorrido";
      tr.addEventListener("click", () => onSelect(row.track, true));
    }
    return tr;
  });
  return table(
    [["Nivel"], ["Resultado"], ["Tiempo", "num"], ["Daño recibido"], ["Muertes"], ["Enemigos", "num"],
      ["Llave"], ["Corazones"], ["Precisión", "num"], ["Monedas", "num"], ["Armas"]],
    trs,
    "Esta partida no tiene niveles registrados.",
  );
}

// --- Route replay ------------------------------------------------------------------

function initialTrack(tracks, params) {
  const level = Number(params.get("level"));
  const attempt = Number(params.get("attempt") || 1);
  const index = tracks.findIndex((t) => t.level === level && t.attempt === attempt);
  // Without a choice, the last level: where the run ended.
  return index >= 0 ? index : tracks.length - 1;
}

export async function renderRun({ arg, params, body, stale }) {
  const id = encodeURIComponent(arg);
  const [run, tracks, sprites] = await Promise.all([
    api(`/api/runs/${id}`), api(`/api/runs/${id}/levels`), loadSprites(),
  ]);
  if (stale()) return;
  const rows = breakdownRows(run, tracks);
  const tabs = h("div", { class: "level-tabs", role: "tablist" });
  const stage = h("div", {});
  const replayPanel = h("div", { class: "panel ice" },
    h("h2", { class: "panel-title" }, "Recorrido y telemetría"),
    tracks.length
      ? [h("p", { class: "muted" }, "El mapa del nivel con el camino del jugador y lo que pasó en cada punto. Pasá el mouse por un ícono para ver el detalle."), tabs, stage]
      : emptyState("Esta partida no tiene telemetría de niveles: el juego la sube al terminar cada nivel."));
  const breakdown = breakdownTable(rows, select);

  function select(index, scroll = false) {
    const track = tracks[index];
    if (!track) return;
    for (const [i, tab] of [...tabs.children].entries()) {
      tab.classList.toggle("active", i === index);
      tab.setAttribute("aria-selected", String(i === index));
    }
    for (const tr of breakdown.querySelectorAll("tbody tr")) tr.classList.toggle("selected", tr.dataset.track === String(index));
    fill(stage, routeReplay(track, sprites));
    setParams({ level: track.level, attempt: track.attempt > 1 ? track.attempt : "" }, { silent: true });
    if (scroll) replayPanel.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  fill(tabs, tracks.map((t, i) => h("button", {
    class: "btn small", type: "button", role: "tab", title: t.label, onclick: () => select(i),
  }, t.attempt > 1 ? `${shortLabel(t)} · intento ${t.attempt}` : shortLabel(t))));

  fill(body,
    h("a", { class: "back", href: hrefTo("partidas") }, "« Volver al historial"),
    runHeader(run),
    h("div", { class: "panel" },
      h("h2", { class: "panel-title" }, "Niveles"),
      h("p", { class: "muted" }, tracks.length
        ? "Cada nivel jugado. Clic en una fila para ver su recorrido."
        : "Calculado con los eventos de la partida."),
      breakdown),
    replayPanel,
    eventsPanel(run.events));
  if (tracks.length) select(initialTrack(tracks, params));
}
