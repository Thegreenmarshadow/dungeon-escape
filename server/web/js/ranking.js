// Ranking: the best finished normal-mode runs.

import { api, cards, emptyState, formatDate, formatDuration, formatNumber, h, playerCell, table, td } from "./dom.js";
import { hrefTo } from "./state.js";

const RANKING_SIZE = 20;

export async function renderRanking({ body, player, stale }) {
  const board = await api("/api/leaderboard", { limit: RANKING_SIZE, player });
  if (stale()) return;
  if (board.entries.length === 0) {
    body.replaceChildren(emptyState(player
      ? `${player} todavía no terminó partidas en modo normal.`
      : "Todavía no hay partidas terminadas."));
    return;
  }
  const best = board.entries[0];
  const rows = board.entries.map((e) => h("tr", {},
    td(h("span", { class: `rank r${e.rank}` }, `#${e.rank}`)),
    td(playerCell(e.player_name, e.player_id)),
    td(formatNumber(e.score), "num score"),
    td(e.level_reached, "num"),
    td(e.enemies_killed, "num"),
    td(e.coins_collected, "num"),
    td(formatDuration(e.duration_s), "num"),
    td(formatDate(e.ended_at)),
    td(h("a", { href: hrefTo("partida", e.run_id) }, "Ver")),
  ));
  body.replaceChildren(
    cards([
      ["orb", formatNumber(best.score), `Récord · ${best.player_name}`],
      ["reaper", board.best_level, "Nivel máximo alcanzado"],
    ]),
    h("h3", {}, player ? `Mejores partidas de ${best.player_name}` : `Top ${RANKING_SIZE}`),
    table(
      [["#"], ["Jugador"], ["Puntos", "num"], ["Nivel", "num"], ["Enemigos", "num"],
        ["Monedas", "num"], ["Duración", "num"], ["Fecha"], [""]],
      rows,
      "Todavía no hay partidas terminadas.",
    ),
  );
}
