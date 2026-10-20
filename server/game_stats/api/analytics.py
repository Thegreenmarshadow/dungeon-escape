from typing import Annotated, Any

from fastapi import APIRouter, Query

from .. import analytics
from ..models import Mode
from .dependencies import Repository

router = APIRouter(tags=["analytics"])


@router.get("/api/analytics")
def get_analytics(
    repo: Repository,
    player: Annotated[str | None, Query(max_length=32)] = None,
    level: Annotated[int | None, Query(ge=1, le=9999)] = None,
    version: Annotated[str | None, Query(max_length=32)] = None,
    mode: Mode | None = None,
) -> dict[str, Any]:
    """Analytics of the uploaded level files that match the filters: per-level
    table, automatic warnings, planned vs measured difficulty and heatmaps per
    map. The demo stays out of the per-level numbers unless mode=demo."""
    levels = repo.level_data(player=player, level=level, version=version, mode=mode)
    excluded = () if mode == "demo" else analytics.EXCLUDED_MODES
    rows = analytics.level_stats(levels, excluded)
    return {
        "options": repo.level_filter_options(),
        "files": len(levels),
        "levels": rows,
        "insights": analytics.insights(rows),
        "chart": analytics.chart_rows(rows, analytics.planned_indexes(levels)),
        "heatmaps": analytics.heatmaps(levels),
        "source_labels": analytics.source_labels(rows),
        "thresholds": {"min_attempts": analytics.MIN_ATTEMPTS},
    }
