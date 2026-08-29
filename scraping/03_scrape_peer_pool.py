"""Build the age-comparison pool: Serie A player stats + birth dates.

Replaces the FBref Big-5 pool (FBref blocks scrapers and its community
mirror went stale). Two datasets that join on player_id:

  peer_stats.csv   season statistics for every ranked Serie A player
                   (paginated leaderboard endpoint, all positions - filter
                   to defenders/age band at analysis time, so changing the
                   cutoff never needs a re-scrape)
  squads.csv       every player in every Serie A squad with birth date,
                   position, height (20 team-squad calls)

The analysis step joins these, computes ages at a reference date, filters
to the comparison group (e.g. defenders born 2007+, 500+ minutes), and
ranks Ahanor's percentiles within it.

Run:  python scraping/03_scrape_peer_pool.py   (run 01 first is NOT required)
"""

from sofascore import (
    SEASON_NAME,
    SERIE_A_ID,
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


def find_season_id(client: SofascoreClient) -> int:
    """Serie A season id for SEASON_NAME (e.g. '25/26')."""
    body = client.get("unique-tournament", SERIE_A_ID, "seasons")
    for season in (body or {}).get("seasons", []):
        if season.get("year") == SEASON_NAME:
            return season["id"]
    available = [s.get("year") for s in (body or {}).get("seasons", [])][:8]
    raise SystemExit(
        f"Season {SEASON_NAME!r} not found; Sofascore lists {available}. "
        "Adjust SEASON_NAME in sofascore.py"
    )


def fetch_leaderboard(client: SofascoreClient, season_id: int) -> list[dict]:
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
                "unique-tournament", SERIE_A_ID, "season", season_id, "statistics",
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
        print(f"leaderboard page {page + 1}: {len(page_rows)} players "
              f"({len(rows)} total)")
        if len(page_rows) < PAGE_SIZE:
            break
    return rows


def fetch_squads(client: SofascoreClient, season_id: int) -> list[dict]:
    body = client.get(
        "unique-tournament", SERIE_A_ID, "season", season_id, "standings", "total"
    )
    teams = parse_standings_team_ids(body)
    if not teams:
        raise SystemExit("No teams in standings - check season id / endpoint")
    print(f"{len(teams)} teams in standings")

    rows: list[dict] = []
    for team_id, team_name in teams:
        body = client.get("team", team_id, "players", ok404=True)
        squad = parse_squad(body, team_id, team_name)
        print(f"squad {team_name}: {len(squad)} players")
        rows.extend(squad)
    return rows


def main() -> None:
    client = SofascoreClient()
    season_id = find_season_id(client)
    print(f"Serie A {SEASON_NAME} -> season id {season_id}")

    if not output_exists("peer_stats.csv"):
        write_csv(fetch_leaderboard(client, season_id), "peer_stats.csv")

    if not output_exists("squads.csv"):
        write_csv(fetch_squads(client, season_id), "squads.csv")


if __name__ == "__main__":
    main()
