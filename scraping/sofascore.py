"""Shared Sofascore API client + parsing helpers for the Ahanor analysis.

Sofascore has no official public API; these are the JSON endpoints the
sofascore.com frontend itself calls. That means:
  * fine for a personal project at this volume, but technically against
    their ToS - keep the throttle, don't hammer;
  * endpoints can change shape without notice, so all parsing lives in
    small pure functions here (easy to fix, easy to test offline);
  * requests without a browser-like User-Agent are rejected with 403.

Every scrape script imports this module. Parsing functions are pure
(dict in -> plain data out) and covered by tests/test_parsing.py.
"""

from __future__ import annotations

import os
import time
from datetime import date, datetime, timezone
from pathlib import Path

# Sofascore's bot protection fingerprints the TLS handshake, and Python's
# `requests` has a recognizable non-browser fingerprint - plain requests get
# HTTP 403 no matter what headers they send. curl_cffi impersonates a real
# Chrome fingerprint and is a near drop-in replacement, so it's the primary
# HTTP stack; plain requests stays as a fallback so the module still imports
# (and offline tests still run) without it.
try:
    from curl_cffi import requests

    HAS_CURL_CFFI = True
except ImportError:
    import requests

    HAS_CURL_CFFI = False

# curl_cffi calls its base network exception RequestsError; requests calls it
# RequestException. Resolve whichever the imported stack provides.
NETWORK_ERROR = getattr(
    requests, "RequestsError", getattr(requests, "RequestException", Exception)
)

# Tried in order; a 403 on one host falls through to the next. Both serve the
# same API - api.sofascore.com is the classic host, www.sofascore.com/api is
# what the website frontend itself calls these days.
BASE_URLS = [
    "https://api.sofascore.com/api/v1",
    "https://www.sofascore.com/api/v1",
]

# ---- constants ---------------------------------------------------------------
PLAYER_ID = 1634980  # https://www.sofascore.com/football/player/honest-ahanor/1634980
PLAYER_NAME = "Honest Ahanor"
SERIE_A_ID = 23           # Sofascore uniqueTournament id for Serie A
SEASON_NAME = "25/26"     # season label as Sofascore prints it (his Atalanta season)

# The Big 5 leagues by Sofascore uniqueTournament id. The peer-pool scraper
# loops these; slugs name the per-league cache files. If a scrape prints an
# unexpected league name next to an id, fix the id here.
BIG5_LEAGUES = {
    "premier-league": 17,
    "laliga": 8,
    "serie-a": 23,
    "bundesliga": 35,
    "ligue-1": 34,
}

# Age filter for the comparison pool: "under 23" as of the season's end.
REFERENCE_DATE = date(2026, 6, 30)
AGE_MAX = 23              # keep players with age < AGE_MAX at REFERENCE_DATE
MIN_MINUTES = 600         # pool entry requires this many league minutes
CUTOFF_DATE = date(2025, 8, 1)  # ignore matches before this (widen for Genoa era)

DATA_RAW = Path(__file__).resolve().parent.parent / "data" / "raw"

# Scrape once, then work from disk: scripts skip outputs that already exist.
# Re-scrape with FORCE_REFRESH=1 (or delete files in data/raw/).
FORCE_REFRESH = os.environ.get("FORCE_REFRESH") == "1"

MIN_REQUEST_INTERVAL = 1.5  # seconds between requests (~40/min max). Keep it.

# UA matches the Chrome fingerprint curl_cffi impersonates. Referer makes the
# request look like it came from a sofascore.com page, as the real ones do.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
    "Referer": "https://www.sofascore.com/",
}


class SofascoreClient:
    """Thin HTTP wrapper: throttling, retries, host fallback, one place for headers."""

    def __init__(self) -> None:
        if HAS_CURL_CFFI:
            self.session = requests.Session(impersonate="chrome")
        else:
            print(
                "WARNING: curl_cffi not installed - falling back to plain "
                "requests, which Sofascore usually rejects with HTTP 403. "
                "Run: pip install -r requirements.txt"
            )
            self.session = requests.Session()
        self.session.headers.update(HEADERS)
        self._last_request = 0.0

    def get(self, *path, params: dict | None = None, ok404: bool = False):
        """GET <base>/<path parts joined by />. Returns parsed JSON.

        ok404=True returns None on a 404 instead of raising - Sofascore uses
        404 for "no data here" (e.g. no heatmap for an unused sub), which is
        an answer, not an error. Retries transient failures (429/5xx/network)
        with exponential backoff; a 403 falls through to the next base host.
        """
        suffix = "/".join(str(p) for p in path)
        for base in BASE_URLS:
            url = f"{base}/{suffix}"
            for attempt in range(4):
                self._throttle()
                try:
                    resp = self.session.get(url, params=params, timeout=30)
                except NETWORK_ERROR as exc:
                    if attempt == 3:
                        raise
                    print(f"  network error ({exc}), retrying...")
                    time.sleep(2**attempt)
                    continue
                if resp.status_code == 404 and ok404:
                    return None
                if resp.status_code == 403:
                    print(f"  HTTP 403 from {base}, trying next host...")
                    break  # next base URL
                if resp.status_code in (429, 500, 502, 503, 504) and attempt < 3:
                    wait = 2 ** (attempt + 1)
                    print(f"  HTTP {resp.status_code}, backing off {wait}s...")
                    time.sleep(wait)
                    continue
                resp.raise_for_status()
                return resp.json()
        raise RuntimeError(
            f"HTTP 403 from every Sofascore host for /{suffix} "
            f"(curl_cffi active: {HAS_CURL_CFFI}). If curl_cffi is active, "
            "Sofascore has likely tightened its bot protection again - "
            "see the README troubleshooting section."
        )

    def _throttle(self) -> None:
        elapsed = time.monotonic() - self._last_request
        if elapsed < MIN_REQUEST_INTERVAL:
            time.sleep(MIN_REQUEST_INTERVAL - elapsed)
        self._last_request = time.monotonic()


# ---- small shared helpers ----------------------------------------------------

def output_exists(filename: str) -> bool:
    """True when the output is already on disk and no refresh is forced."""
    path = DATA_RAW / filename
    if FORCE_REFRESH:
        return False
    if path.exists():
        print(f"skip (cached): {path}")
        return True
    return False


def write_csv(rows: list[dict], filename: str) -> None:
    """Write list-of-dicts to data/raw/<filename> (union of keys as header)."""
    import csv

    DATA_RAW.mkdir(parents=True, exist_ok=True)
    path = DATA_RAW / filename
    fieldnames: list[str] = []
    for row in rows:  # preserve first-seen order, cover all keys
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"saved {path} ({len(rows)} rows)")


def ts_to_date(timestamp) -> date | None:
    if timestamp is None:
        return None
    return datetime.fromtimestamp(int(timestamp), tz=timezone.utc).date()


# ---- pure parsing functions (tested offline in tests/test_parsing.py) --------

def parse_event(ev: dict) -> dict:
    """Flatten one entry of /player/{id}/events/last/{page} 'events'."""
    tournament = (ev.get("tournament") or {}).get("uniqueTournament") or {}
    return {
        "event_id": ev.get("id"),
        "date": ts_to_date(ev.get("startTimestamp")),
        "tournament": tournament.get("name"),
        "tournament_id": tournament.get("id"),
        "home_team": (ev.get("homeTeam") or {}).get("name"),
        "away_team": (ev.get("awayTeam") or {}).get("name"),
        "status": (ev.get("status") or {}).get("type"),
    }


def parse_heatmap(body: dict | None) -> list[dict]:
    """Point cloud from a heatmap response, in Sofascore's 0-100 pitch space.

    The point list has been observed under both 'heatmap' (per-match) and
    'points' (season aggregate) keys; points sometimes carry a 'count'
    weight and sometimes don't (-> weight 1).
    """
    if not body:
        return []
    points = body.get("heatmap") or body.get("points") or []
    return [
        {"x": p.get("x"), "y": p.get("y"), "count": p.get("count", 1)}
        for p in points
    ]


def parse_season_stats(body: dict | None) -> dict:
    """Flat stats dict from /player/.../statistics/overall (or {} if none)."""
    if not body:
        return {}
    stats = body.get("statistics") or {}
    # everything scalar; drop nested keys defensively
    return {k: v for k, v in stats.items() if not isinstance(v, (dict, list))}


def parse_statistics_seasons(body: dict | None) -> list[dict]:
    """Flatten /player/{id}/statistics/seasons into (tournament, season) rows."""
    rows = []
    for ut in (body or {}).get("uniqueTournamentSeasons", []):
        tournament = ut.get("uniqueTournament") or {}
        for season in ut.get("seasons", []):
            rows.append(
                {
                    "tournament_id": tournament.get("id"),
                    "tournament": tournament.get("name"),
                    "season_id": season.get("id"),
                    "season_name": season.get("year"),
                }
            )
    return rows


def parse_squad(body: dict | None, team_id: int, team_name: str) -> list[dict]:
    """Flatten /team/{id}/players into one row per player (with birth date)."""
    rows = []
    for entry in (body or {}).get("players", []):
        player = entry.get("player") or {}
        rows.append(
            {
                "player_id": player.get("id"),
                "player_name": player.get("name"),
                "position": player.get("position"),
                "birth_date": ts_to_date(player.get("dateOfBirthTimestamp")),
                "height_cm": player.get("height"),
                "preferred_foot": player.get("preferredFoot"),
                "team_id": team_id,
                "team_name": team_name,
            }
        )
    return rows


def parse_standings_team_ids(body: dict | None) -> list[tuple[int, str]]:
    """(team_id, team_name) pairs from /unique-tournament/.../standings/total."""
    teams = []
    for standing in (body or {}).get("standings", []):
        for row in standing.get("rows", []):
            team = row.get("team") or {}
            if team.get("id") is not None:
                teams.append((team["id"], team.get("name")))
    return teams


def parse_characteristics(body: dict | None) -> list[str]:
    """Detailed position codes (e.g. ['CB', 'LB']) from /player/{id}/characteristics.

    Best-effort: this endpoint is the one place Sofascore exposes
    centre-back vs full-back granularity (the leaderboard only says 'D').
    Returns [] whenever the response is missing or shaped differently.
    """
    if not body:
        return []
    positions = body.get("positions") or []
    return [p for p in positions if isinstance(p, str)]


def parse_leaderboard_page(body: dict | None) -> list[dict]:
    """Flatten one page of /unique-tournament/.../statistics results."""
    rows = []
    for result in (body or {}).get("results", []):
        player = result.get("player") or {}
        team = result.get("team") or {}
        row = {
            "player_id": player.get("id"),
            "player_name": player.get("name"),
            "position": player.get("position"),
            "team_id": team.get("id"),
            "team_name": team.get("name"),
        }
        for key, value in result.items():
            if key not in ("player", "team") and not isinstance(value, (dict, list)):
                row[key] = value
        rows.append(row)
    return rows
