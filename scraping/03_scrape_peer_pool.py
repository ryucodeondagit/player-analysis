"""Build the raw comparison pool: player stats + birth dates for ALL Big-5 leagues.

For each of the five leagues (see BIG5_LEAGUES in sofascore.py):
  * the season leaderboard - stats for every ranked player, all positions
    (position/age filtering happens later, so changing cutoffs never
    triggers a re-scrape)
  * every squad in the league - birth dates, coarse positions, heights

Outputs (data/raw/):
  peer_stats_<league>.csv / squads_<league>.csv   per-league caches, so an
                                                  interrupted run resumes at
                                                  the next league
  peer_stats.csv / squads.csv                     all leagues combined, with
                                                  a `league` column

Roughly 130 requests total (~4 minutes at the built-in throttle).

Run:  python scraping/03_scrape_peer_pool.py
"""

import csv

from sofascore import (
    BIG5_LEAGUES,
    DATA_RAW,
    SEASON_NAME,
    SofascoreClient,
    output_exists,
    parse_leaderboard_page,
    parse_squad,
    parse_standings_team_ids,
    write_csv,
)

# Stat fields requested from the leaderboard endpoint (the same ones the
# sofascore.com "player statistics" page requests). If Sofascore rejects the
# list (HTTP 400 - field names drift occasionally), we retry with CORE_FIELDS.
FIELDS = [
    "rating", "appearances", "minutesPlayed", "goals", "assists",
    "expectedAssists", "tackles", "interceptions", "clearances",
    "ballRecovery", "blockedShots", "errorLeadToGoal",
    "totalDuelsWon", "totalDuelsWonPercentage",
    "groundDuelsWon", "groundDuelsWonPercentage",
    "aerialDuelsWon", "aerialDuelsWonPercentage",
    "accuratePasses", "accuratePassesPercentage",
    "accurateLongBalls", "accurateLongBallsPercentage",
    "keyPasses", "bigChancesCreated", "successfulDribbles",
    "possessionLost", "fouls", "wasFouled",
    "yellowCards", "redCards",
]
CORE_FIELDS = ["rating", "appearances", "minutesPlayed", "goals", "assists",
               "tackles", "interceptions", "accuratePasses"]

PAGE_SIZE = 100
MAX_PAGES = 20  # safety stop; a 20-team league has < 700 ranked players


def find_season_id(client: SofascoreClient, league_id: int, league: str) -> int:
    """The league's season id for SEASON_NAME (e.g. '25/26')."""
    body = client.get("unique-tournament", league_id, "seasons")
    for season in (body or {}).get("seasons", []):
        if season.get("year") == SEASON_NAME:
            return season["id"]
    available = [s.get("year") for s in (body or {}).get("seasons", [])][:8]
    raise SystemExit(
        f"Season {SEASON_NAME!r} not found for {league}; Sofascore lists "
        f"{available}. Adjust SEASON_NAME in sofascore.py"
    )


def fetch_leaderboard(client: SofascoreClient, league_id: int, season_id: int) -> list[dict]:
    fields = FIELDS
    rows: list[dict] = []
    for page in range(MAX_PAGES):
        params = {
            "limit": PAGE_SIZE,
            "offset": page * PAGE_SIZE,
            "accumulation": "total",       # season totals, not per-game
            "fields": ",".join(fields),
            "order": "-rating",
        }
        try:
            body = client.get(
                "unique-tournament", league_id, "season", season_id, "statistics",
                params=params,
            )
        except Exception as exc:  # noqa: BLE001 - one focused fallback, then raise
            if fields is FIELDS and "400" in str(exc):
                print("field list rejected (HTTP 400) - retrying with core fields; "
                      "update FIELDS to match what sofascore.com currently requests")
                fields = CORE_FIELDS
                continue
            raise
        page_rows = parse_leaderboard_page(body)
        if not page_rows:
            break
        rows.extend(page_rows)
        print(f"  leaderboard page {page + 1}: {len(page_rows)} players "
              f"({len(rows)} total)")
        if len(page_rows) < PAGE_SIZE:
            break
    return rows


def fetch_squads(client: SofascoreClient, league_id: int, season_id: int) -> list[dict]:
    body = client.get(
        "unique-tournament", league_id, "season", season_id, "standings", "total"
    )
    teams = parse_standings_team_ids(body)
    if not teams:
        raise SystemExit("No teams in standings - check league/season id")
    print(f"  {len(teams)} teams in standings")

    rows: list[dict] = []
    for team_id, team_name in teams:
        body = client.get("team", team_id, "players", ok404=True)
        squad = parse_squad(body, team_id, team_name)
        print(f"  squad {team_name}: {len(squad)} players")
        rows.extend(squad)
    return rows


def combine(per_league_files: list[str], out: str) -> None:
    """Concatenate per-league CSVs (adding nothing - league col already there)."""
    rows: list[dict] = []
    for filename in per_league_files:
        with open(DATA_RAW / filename, encoding="utf-8") as fh:
            rows.extend(csv.DictReader(fh))
    write_csv(rows, out)


def main() -> None:
    client = SofascoreClient()

    stats_files, squad_files = [], []
    for league, league_id in BIG5_LEAGUES.items():
        stats_file = f"peer_stats_{league}.csv"
        squad_file = f"squads_{league}.csv"
        stats_files.append(stats_file)
        squad_files.append(squad_file)

        if output_exists(stats_file) and output_exists(squad_file):
            continue
        season_id = find_season_id(client, league_id, league)
        print(f"{league} {SEASON_NAME} -> season id {season_id}")

        if not output_exists(stats_file):
            rows = fetch_leaderboard(client, league_id, season_id)
            for row in rows:
                row["league"] = league
            write_csv(rows, stats_file)

        if not output_exists(squad_file):
            rows = fetch_squads(client, league_id, season_id)
            for row in rows:
                row["league"] = league
            write_csv(rows, squad_file)

    combine(stats_files, "peer_stats.csv")
    combine(squad_files, "squads.csv")


if __name__ == "__main__":
    main()
