"""Identify the comparison club's centre-backs (COMPARE_CLUB in sofascore.py).

Takes the club's defenders from squads.csv, fetches each one's detailed
positions (a handful of requests, shared characteristics cache), and writes
the centre-backs to club_cbs.csv. The R side joins their stats from
pool_defenders_all.csv for the "gap he fills" chart.

Run AFTER 03 and 04:  python scraping/05_scrape_club_cbs.py
"""

import csv

from sofascore import (
    CB_CODES,
    COMPARE_CLUB,
    DATA_RAW,
    SofascoreClient,
    fetch_characteristics,
    load_characteristics_cache,
    output_exists,
    write_csv,
)


def main() -> None:
    if output_exists("club_cbs.csv"):
        return

    with open(DATA_RAW / "squads.csv", encoding="utf-8") as fh:
        squads = list(csv.DictReader(fh))

    club = [r for r in squads
            if COMPARE_CLUB.lower() in (r.get("team_name") or "").lower()
            and r.get("position") == "D"]
    if not club:
        teams = sorted({r.get("team_name") for r in squads})
        raise SystemExit(
            f"No defenders found for {COMPARE_CLUB!r}. Team names in "
            f"squads.csv include: {teams[:30]}"
        )
    print(f"{COMPARE_CLUB}: {len(club)} defenders in squad")

    cache = load_characteristics_cache()
    fetch_characteristics(SofascoreClient(), {r["player_id"] for r in club}, cache)

    rows = []
    for player in club:
        positions = cache.get(player["player_id"], "")
        is_cb = bool(CB_CODES & set(positions.split("|"))) if positions else False
        print(f"  {player['player_name']:24s} {positions or '(unknown)'}"
              f"{'  -> CB' if is_cb else ''}")
        rows.append({
            "player_id": player["player_id"],
            "player_name": player["player_name"],
            "team_name": player["team_name"],
            "birth_date": player.get("birth_date"),
            "positions_detail": positions,
            "is_cb": str(is_cb),
        })

    n_cb = sum(1 for r in rows if r["is_cb"] == "True")
    if n_cb == 0:
        print("WARNING: no CBs tagged - the R chart will fall back to all "
              f"{COMPARE_CLUB} defenders")
    write_csv(rows, "club_cbs.csv")


if __name__ == "__main__":
    main()
