"""Offline tests for the Sofascore parsing + pagination logic.

No network: every test feeds mock JSON shaped like real Sofascore responses
(both shape variants where two have been observed in the wild).

Run:  python tests/test_parsing.py
"""

import importlib.util
import sys
from datetime import date, datetime, timezone
from pathlib import Path

SCRAPING = Path(__file__).resolve().parent.parent / "scraping"
sys.path.insert(0, str(SCRAPING))

from sofascore import (  # noqa: E402
    parse_event,
    parse_heatmap,
    parse_leaderboard_page,
    parse_season_stats,
    parse_squad,
    parse_standings_team_ids,
    parse_statistics_seasons,
)


def ts(day: str) -> int:
    return int(datetime.fromisoformat(day).replace(tzinfo=timezone.utc).timestamp())


def test_parse_event():
    ev = {
        "id": 101,
        "startTimestamp": ts("2025-10-01"),
        "tournament": {"uniqueTournament": {"id": 23, "name": "Serie A"}},
        "homeTeam": {"name": "Atalanta"},
        "awayTeam": {"name": "Inter"},
        "status": {"type": "finished"},
    }
    row = parse_event(ev)
    assert row == {
        "event_id": 101, "date": date(2025, 10, 1),
        "tournament": "Serie A", "tournament_id": 23,
        "home_team": "Atalanta", "away_team": "Inter", "status": "finished",
    }
    # friendly without uniqueTournament must not crash
    row = parse_event({"id": 5, "startTimestamp": ts("2025-09-01"), "tournament": {}})
    assert row["tournament"] is None and row["event_id"] == 5


def test_parse_heatmap():
    # per-match shape: 'heatmap' key with counts
    body = {"heatmap": [{"x": 23, "y": 81, "count": 4}, {"x": 50, "y": 50}]}
    pts = parse_heatmap(body)
    assert pts[0] == {"x": 23, "y": 81, "count": 4}
    assert pts[1]["count"] == 1  # missing count -> weight 1
    # season-aggregate shape: 'points' key
    assert parse_heatmap({"points": [{"x": 1, "y": 2, "count": 9}]})[0]["count"] == 9
    # empty / missing
    assert parse_heatmap(None) == []
    assert parse_heatmap({}) == []


def test_parse_season_stats():
    body = {"statistics": {"rating": 6.83, "tackles": 41,
                           "type": {"nested": "dropped"}, "arr": [1]}}
    stats = parse_season_stats(body)
    assert stats == {"rating": 6.83, "tackles": 41}
    assert parse_season_stats(None) == {}


def test_parse_statistics_seasons():
    body = {"uniqueTournamentSeasons": [
        {"uniqueTournament": {"id": 23, "name": "Serie A"},
         "seasons": [{"id": 76457, "year": "25/26"}, {"id": 63515, "year": "24/25"}]},
        {"uniqueTournament": {"id": 328, "name": "Coppa Italia"},
         "seasons": [{"id": 70000, "year": "25/26"}]},
    ]}
    rows = parse_statistics_seasons(body)
    assert len(rows) == 3
    assert rows[0] == {"tournament_id": 23, "tournament": "Serie A",
                       "season_id": 76457, "season_name": "25/26"}


def test_parse_squad_and_standings():
    squad = parse_squad(
        {"players": [{"player": {"id": 1634980, "name": "Honest Ahanor",
                                 "position": "D",
                                 "dateOfBirthTimestamp": ts("2008-02-23"),
                                 "height": 185, "preferredFoot": "Left"}}]},
        team_id=2686, team_name="Atalanta",
    )
    assert squad[0]["birth_date"] == date(2008, 2, 23)
    assert squad[0]["team_name"] == "Atalanta"

    teams = parse_standings_team_ids(
        {"standings": [{"rows": [{"team": {"id": 2686, "name": "Atalanta"}},
                                 {"team": {"id": 2697, "name": "Inter"}}]}]}
    )
    assert teams == [(2686, "Atalanta"), (2697, "Inter")]


def test_parse_leaderboard_page():
    body = {"results": [{
        "player": {"id": 1634980, "name": "Honest Ahanor", "position": "D"},
        "team": {"id": 2686, "name": "Atalanta"},
        "rating": 6.83, "tackles": 41, "nested": {"drop": 1},
    }]}
    rows = parse_leaderboard_page(body)
    assert rows[0]["player_name"] == "Honest Ahanor"
    assert rows[0]["rating"] == 6.83 and rows[0]["tackles"] == 41
    assert "nested" not in rows[0]
    assert parse_leaderboard_page(None) == []


def test_fetch_matches_pagination():
    """fetch_matches stops paging once past the cutoff and de-duplicates."""
    spec = importlib.util.spec_from_file_location(
        "scrape_heatmaps", SCRAPING / "02_scrape_heatmaps.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    def event(eid, day):
        return {"id": eid, "startTimestamp": ts(day),
                "tournament": {"uniqueTournament": {"id": 23, "name": "Serie A"}},
                "homeTeam": {"name": "A"}, "awayTeam": {"name": "B"},
                "status": {"type": "finished"}}

    pages = {
        0: {"events": [event(101, "2025-10-01"), event(102, "2025-10-08")],
            "hasNextPage": True},
        1: {"events": [event(102, "2025-10-08"), event(90, "2024-01-01")],
            "hasNextPage": True},   # oldest is past the cutoff -> stop here
        2: {"events": [event(80, "2023-01-01")], "hasNextPage": False},
    }
    requested = []

    class StubClient:
        def get(self, *path, **kwargs):
            page = path[-1]
            requested.append(page)
            return pages[page]

    matches = mod.fetch_matches(StubClient())
    assert requested == [0, 1]           # never fetched page 2
    assert [m["event_id"] for m in matches] == [90, 101, 102]  # deduped, sorted


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"PASS {name}")
            except AssertionError as exc:
                failures += 1
                print(f"FAIL {name}: {exc}")
    raise SystemExit(1 if failures else 0)
