"""Scrape the subject's heatmap data from Sofascore.

Two kinds, because they serve different plots:
  * per-match point clouds  -> heatmap by match / faceted small multiples
  * season aggregate points -> one smooth season heatmap per competition

Outputs (data/raw/):
  matches.csv          his played matches (all, unfiltered - filter at plot time)
  heatmap_points.csv   per-match (x, y, count) points since CUTOFF_DATE,
                       tagged with match metadata
  season_heatmaps.csv  aggregate (x, y, count) per (tournament, season)

Coordinates are Sofascore's 0-100 x 0-100 pitch space, attack left-to-right.

Run:  python scraping/02_scrape_heatmaps.py
"""

import csv
from datetime import date

from sofascore import (
    CUTOFF_DATE,
    DATA_RAW,
    SofascoreClient,
    output_exists,
    parse_event,
    parse_heatmap,
    subject_id,
    write_csv,
)


def fetch_matches(client: SofascoreClient, player_id: int) -> list[dict]:
    """Page backwards through played matches until past the cutoff date."""
    matches: list[dict] = []
    page = 0
    while True:
        body = client.get("player", player_id, "events", "last", page, ok404=True)
        events = (body or {}).get("events", [])
        if not events:
            break
        parsed = [parse_event(ev) for ev in events]
        matches.extend(parsed)
        dates = [m["date"] for m in parsed if m["date"] is not None]
        # everything on later pages is older still - stop once past the cutoff
        if dates and min(dates) < CUTOFF_DATE:
            break
        if not (body or {}).get("hasNextPage"):
            break
        page += 1
    # de-duplicate (a match can appear on two adjacent pages), oldest first
    unique = {m["event_id"]: m for m in matches}
    return sorted(unique.values(), key=lambda m: (m["date"] or CUTOFF_DATE))


def main() -> None:
    client = SofascoreClient()
    player_id = subject_id(client)

    # ---- match list ----------------------------------------------------------
    if not output_exists("matches.csv"):
        matches = fetch_matches(client, player_id)
        if not matches:
            raise SystemExit("No matches returned - check the subject id / endpoint")
        write_csv(matches, "matches.csv")
    else:
        with open(DATA_RAW / "matches.csv", encoding="utf-8") as fh:
            matches = list(csv.DictReader(fh))
        for m in matches:  # csv round-trip: restore types the loop below needs
            m["date"] = date.fromisoformat(m["date"]) if m["date"] else None

    # ---- per-match heatmaps --------------------------------------------------
    if not output_exists("heatmap_points.csv"):
        target = [
            m for m in matches
            if m["status"] == "finished" and m["date"] and m["date"] >= CUTOFF_DATE
        ]
        print(f"{len(target)} finished matches since {CUTOFF_DATE}")

        rows = []
        for match in target:
            print(f"heatmap {match['date']}  {match['home_team']} vs {match['away_team']}")
            body = client.get(
                "event", match["event_id"], "player", player_id, "heatmap",
                ok404=True,  # 404 = unused sub / competition without heatmaps
            )
            for point in parse_heatmap(body):
                rows.append(
                    {
                        "event_id": match["event_id"],
                        "date": match["date"],
                        "tournament": match["tournament"],
                        "home_team": match["home_team"],
                        "away_team": match["away_team"],
                        **point,
                    }
                )
        write_csv(rows, "heatmap_points.csv")

    # ---- season aggregate heatmaps (best effort) -----------------------------
    # Uses the (tournament, season) pairs collected by 01_scrape_player.py.
    if not output_exists("season_heatmaps.csv"):
        seasons_path = DATA_RAW / "player_seasons.csv"
        if not seasons_path.exists():
            print("player_seasons.csv missing - run 01_scrape_player.py first; "
                  "skipping season aggregate heatmaps")
            return
        with open(seasons_path, encoding="utf-8") as fh:
            seasons = list(csv.DictReader(fh))

        rows = []
        for season in seasons:
            body = client.get(
                "player", player_id,
                "unique-tournament", season["tournament_id"],
                "season", season["season_id"],
                "heatmap", "overall",
                ok404=True,
            )
            points = parse_heatmap(body)
            print(f"season heatmap: {season['tournament']} {season['season_name']}"
                  f" -> {len(points)} points")
            for point in points:
                rows.append(
                    {
                        "tournament": season["tournament"],
                        "season_name": season["season_name"],
                        **point,
                    }
                )
        write_csv(rows, "season_heatmaps.csv")


if __name__ == "__main__":
    main()
