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
    names_match,
    parse_characteristics,
    parse_event,
    parse_heatmap,
    parse_leaderboard_page,
    parse_search_players,
    parse_season_stats,
    parse_squad,
    parse_standings_team_ids,
    parse_statistics_seasons,
    pick_season_row,
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


def test_parse_characteristics():
    assert parse_characteristics({"positions": ["CB", "LB"]}) == ["CB", "LB"]
    assert parse_characteristics({"positions": [{"odd": 1}, "CB"]}) == ["CB"]
    assert parse_characteristics({}) == []
    assert parse_characteristics(None) == []


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


def test_names_match():
    assert names_match("Enzo Fernández", "Enzo Fernandez")
    assert names_match("Andrey Santos", "Andrey Nascimento dos Santos")
    assert names_match("Moisés Caicedo", "Moisés Caicedo")
    assert not names_match("Jordan Henderson", "Dean Henderson")
    assert not names_match("Enzo Fernández", None)


def test_parse_search_players():
    body = {
        "results": [
            {"type": "team", "entity": {"id": 38, "name": "Chelsea"}},
            {"type": "player", "entity": {
                "id": 1, "name": "Enzo Fernández", "position": "M",
                "team": {"name": "Real Madrid"}}},
            {"type": "player", "entity": {"id": 2, "name": "Enzo Pérez",
                                          "team": {"name": "River Plate"}}},
        ]
    }
    rows = parse_search_players(body)
    assert [r["player_id"] for r in rows] == [1, 2]
    assert rows[0]["team_name"] == "Real Madrid"
    # flat variant
    assert parse_search_players({"players": [{"id": 3, "name": "X"}]})[0]["player_id"] == 3
    assert parse_search_players(None) == []


def test_pick_season_row():
    seasons = [
        {"tournament_id": 7, "tournament": "Champions League", "season_id": 90,
         "season_name": "25/26"},
        {"tournament_id": 34, "tournament": "Ligue 1", "season_id": 91,
         "season_name": "25/26"},
        {"tournament_id": 17, "tournament": "Premier League", "season_id": 80,
         "season_name": "24/25"},
    ]
    # Premier League preferred, but this player has none in 25/26 -> Big-5
    pick = pick_season_row(seasons, "25/26", 17, [17, 8, 23, 35, 34])
    assert pick["season_id"] == 91
    # without an allowed list, first 25/26 row wins
    assert pick_season_row(seasons, "25/26")["season_id"] == 90
    assert pick_season_row(seasons, "23/24") is None
    # csv round-trip: ids come back as strings
    csv_rows = [{**s, "tournament_id": str(s["tournament_id"])} for s in seasons]
    assert pick_season_row(csv_rows, "24/25", 17)["season_id"] == 80


def test_build_midfield_pool():
    spec = importlib.util.spec_from_file_location(
        "build_pool", SCRAPING / "07_build_midfield_pool.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    def to_float(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    stats = [
        {"player_id": "1", "player_name": "Enzo", "minutesPlayed": "2500",
         "keyPasses": "50", "tackles": "40"},
        {"player_id": "2", "player_name": "Mid, short minutes",
         "minutesPlayed": "300", "keyPasses": "3", "tackles": "5"},
        {"player_id": "3", "player_name": "A striker", "minutesPlayed": "2000",
         "keyPasses": "30", "tackles": "10"},
        {"player_id": "4", "player_name": "Pool mid", "minutesPlayed": "1800",
         "keyPasses": "20", "tackles": "60"},
        {"player_id": "5", "player_name": "Essugo (tracked, few minutes)",
         "minutesPlayed": "200", "keyPasses": "1", "tackles": "4"},
    ]
    squads = [  # Enzo (1) has left the league: no squad row
        {"player_id": "2", "position": "M", "birth_date": "2000-01-01"},
        {"player_id": "3", "position": "F", "birth_date": "2000-01-01"},
        {"player_id": "4", "position": "M", "birth_date": "1999-05-05"},
        {"player_id": "5", "position": "M", "birth_date": "2005-03-14"},
    ]
    roster = [
        {"player_id": "1", "role": "departed", "config_name": "Enzo Fernández"},
        {"player_id": "5", "role": "stays", "config_name": "Dário Essugo"},
    ]
    pool = mod.build_pool(stats, squads, roster, ["keyPasses", "tackles"], to_float)
    ids = [p["player_id"] for p in pool]
    assert ids == ["1", "4", "5"]          # tracked survive; F and <600 min drop
    enzo = pool[0]
    assert enzo["position"] == "M" and enzo["role"] == "departed"
    assert enzo["keyPasses_per90"] == 1.8
    assert pool[1]["role"] == "" and pool[1]["birth_date"] == "1999-05-05"
    assert pool[2]["player_name"] == "Dário Essugo"   # short config name wins


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
