// Global stats: totals of every run (or of the filtered player's runs).

import { api, avatar, cards, formatDuration, formatNumber, h, heartIcon, table, td } from "./dom.js";
import { EVENT_LABELS, ITEM_LABELS } from "./labels.js";

export async function renderStats({ body, params, player, stale }) {
  const stats = await api("/api/stats", { mode: params.get("mode"), player });
  if (stale()) return;
  const tiles = cards([
    ["skull", formatNumber(stats.total_runs), "Partidas"],
    ["flag", formatNumber(stats.finished_runs), "Terminadas"],
    [avatar(player || "Jugadores"), formatNumber(stats.total_players), "Jugadores"],
    ["skeleton", formatNumber(stats.total_kills), "Enemigos eliminados"],
    ["key", formatNumber(stats.keys_collected), "Llaves recogidas"],
    [heartIcon(), formatNumber(stats.hearts_collected), "Corazones recogidos"],
    ["spikes", formatNumber(stats.damage_taken), "Daño recibido"],
    ["coin", formatNumber(stats.coins_collected), "Monedas recogidas"],
    ["chest", formatNumber(stats.coins_spent), "Monedas gastadas"],
    ["flask", formatNumber(stats.items_bought), "Compras en la tienda"],
    ["candle", formatNumber(stats.levels_completed), "Niveles superados"],
    ["torch", formatDuration(stats.avg_duration_s), "Duración promedio"],
    ["reaper", stats.best_level, "Nivel máximo"],
    ["orb", formatNumber(stats.best_score), "Mejor puntaje"],
  ]);
  const eventRows = Object.entries(stats.events_by_type).map(([type, count]) => h("tr", {},
    td(EVENT_LABELS[type] || type), td(type, "muted"), td(formatNumber(count), "num")));
  const itemRows = Object.entries(stats.items_bought_by_item || {}).map(([item, count]) => h("tr", {},
    td(ITEM_LABELS[item] || item), td(item, "muted"), td(formatNumber(count), "num")));
  body.replaceChildren(
    tiles,
    h("div", { class: "grid-2" },
      h("div", {},
        h("h3", {}, "Compras por artículo"),
        table([["Artículo"], ["Id"], ["Compras", "num"]], itemRows, "Todavía no hay compras.")),
      h("div", {},
        h("h3", {}, "Eventos por tipo"),
        table([["Evento"], ["Tipo"], ["Cantidad", "num"]], eventRows, "Todavía no hay eventos."))),
  );
}
