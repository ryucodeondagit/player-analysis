"""Build the Premier League midfielder pool for the Chelsea midfield charts.

Joins the Premier League MIDFIELD_SEASON leaderboard with the squad file
(positions, birth dates), keeps midfielders with MIN_MINUTES+ league minutes,
adds per-90 rates, and tags the Chelsea roster rows (role column). Roster
players always survive the filters - they are the subject - and keep their
row even when they have left the league (no squad row: the roster file
supplies their position).

Reads  data/raw/peer_stats_premier-league_25-26.csv   (06 or 03)
       data/raw/squads_premier-league.csv             (06 or 03)
       data/raw/chelsea_midfield.csv                  (06)
Writes data/raw/pool_pl_midfielders.csv

Run AFTER 06:  python scraping/07_build_midfield_pool.py
"""

import csv

from sofascore import (
    DATA_RAW,
    MIDFIELD_SEASON,
    MIN_MINUTES,
    import_script,
    output_exists,
    write_csv,
)

POOL_POSITION = "M"  # Sofascore's coarse squad position for midfielders


def read_csv(filename: str) -> list[dict]:
    path = DATA_RAW / filename
    if not path.exists():
        raise SystemExit(f"{path} missing - run scraping/06_scrape_chelsea_midfield.py first")
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def build_pool(stats: list[dict], squads: list[dict], roster: list[dict],
               per90_fields: list[str], to_float) -> list[dict]:
    """Pure join/filter step (tested offline)."""
    bio_by_id = {row["player_id"]: row for row in squads}
    roster_by_id = {str(r["player_id"]): r for r in roster}

    pool = []
    for row in stats:
        pid = str(row["player_id"])
        bio = bio_by_id.get(pid, {})
        tracked = roster_by_id.get(pid)
        position = bio.get("position") or row.get("position") or (
            POOL_POSITION if tracked else None
        )
        minutes = to_float(row.get("minutesPlayed"))
        if not tracked:
            if position != POOL_POSITION:
                continue
            if not minutes or minutes < MIN_MINUTES:
                continue
        merged = {
            **row,
            # roster players keep their short config name on the charts
            "player_name": tracked["config_name"] if tracked else row.get("player_name"),
            "position": position,
            "birth_date": bio.get("birth_date"),
            "role": tracked["role"] if tracked else "",
            "config_name": tracked["config_name"] if tracked else "",
        }
        for field in per90_fields:
            value = to_float(row.get(field))
            merged[f"{field}_per90"] = (
                round(value / minutes * 90, 3)
                if value is not None and minutes else None
            )
        pool.append(merged)
    return pool


def main() -> None:
    if output_exists("pool_pl_midfielders.csv"):
        return
    season_slug = MIDFIELD_SEASON.replace("/", "-")
    stats = read_csv(f"peer_stats_premier-league_{season_slug}.csv")
    squads = read_csv("squads_premier-league.csv")
    roster = read_csv("chelsea_midfield.csv")

    builder = import_script("04_build_pool")  # PER90_FIELDS + to_float
    pool = build_pool(stats, squads, roster, builder.PER90_FIELDS, builder.to_float)
    n_tracked = sum(1 for p in pool if p["role"])
    print(f"pool: {len(pool)} Premier League midfielders ({MIDFIELD_SEASON}, "
          f"{MIN_MINUTES}+ min), {n_tracked} of {len(roster)} roster players ranked")
    for r in roster:
        if not any(p["player_id"] == str(r["player_id"]) for p in pool):
            print(f"  NOTE: {r['player_name']} ({r['role']}) is not on the "
                  f"{MIDFIELD_SEASON} Premier League leaderboard (other league, "
                  "or no minutes) - he stays out of the scatter; the heatmap "
                  "grid still shows him")
    if not pool:
        raise SystemExit("Empty pool - check the peer_stats/squads files")
    write_csv(pool, "pool_pl_midfielders.csv")


if __name__ == "__main__":
    main()
