"""Scrape the subject's (PLAYER_NAME in sofascore.py) profile and season stats.

Outputs (data/raw/):
  player_profile.csv       one row: bio (birth date, height, foot, position)
  player_seasons.csv       every (tournament, season) Sofascore has stats for
  player_season_stats.csv  one row per (tournament, season) with the full
                           flat stats block (rating, tackles, duels, passes,
                           minutes, ...) - his career line by competition

Run:  python scraping/01_scrape_player.py
"""

import json

from sofascore import (
    DATA_RAW,
    SofascoreClient,
    output_exists,
    parse_season_stats,
    parse_statistics_seasons,
    subject_id,
    ts_to_date,
    write_csv,
)


def main() -> None:
    client = SofascoreClient()
    player_id = subject_id(client)

    # ---- profile -------------------------------------------------------------
    if not output_exists("player_profile.csv"):
        body = client.get("player", player_id)
        player = body.get("player") or {}
        team = player.get("team") or {}
        write_csv(
            [
                {
                    "player_id": player.get("id"),
                    "name": player.get("name"),
                    "birth_date": ts_to_date(player.get("dateOfBirthTimestamp")),
                    "position": player.get("position"),
                    "height_cm": player.get("height"),
                    "preferred_foot": player.get("preferredFoot"),
                    "team": team.get("name"),
                    "shirt_number": player.get("shirtNumber"),
                    "market_value_eur": (player.get("proposedMarketValueRaw") or {}).get("value")
                    if isinstance(player.get("proposedMarketValueRaw"), dict)
                    else player.get("proposedMarketValue"),
                }
            ],
            "player_profile.csv",
        )
        # keep the raw JSON too - handy when a field we didn't map is needed
        (DATA_RAW / "player_profile.json").write_text(
            json.dumps(body, indent=2), encoding="utf-8"
        )

    # ---- which (tournament, season) pairs have stats -------------------------
    seasons = None
    if not output_exists("player_seasons.csv"):
        body = client.get("player", player_id, "statistics", "seasons")
        seasons = parse_statistics_seasons(body)
        if not seasons:
            raise SystemExit(
                "No stats seasons returned - endpoint shape may have changed; "
                "inspect the response of /player/{id}/statistics/seasons"
            )
        write_csv(seasons, "player_seasons.csv")

    # ---- per-season statistics ----------------------------------------------
    if not output_exists("player_season_stats.csv"):
        if seasons is None:  # cached run of the step above
            import csv

            with open(DATA_RAW / "player_seasons.csv", encoding="utf-8") as fh:
                seasons = list(csv.DictReader(fh))

        rows = []
        for season in seasons:
            print(f"stats: {season['tournament']} {season['season_name']}")
            body = client.get(
                "player", player_id,
                "unique-tournament", season["tournament_id"],
                "season", season["season_id"],
                "statistics", "overall",
                ok404=True,
            )
            stats = parse_season_stats(body)
            if not stats:
                print("  (no stats for this season - skipped)")
                continue
            rows.append({**season, **stats})
        write_csv(rows, "player_season_stats.csv")


if __name__ == "__main__":
    main()
