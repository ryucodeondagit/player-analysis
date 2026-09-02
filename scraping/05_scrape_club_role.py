"""Identify the comparison club's same-role players (COMPARE_CLUB, ROLE_CODES).

Takes the club's PLAYER_POSITION players from squads.csv, fetches each one's
detailed positions (a handful of requests, shared characteristics cache),
and tags the ones whose codes overlap ROLE_CODES. The R side joins their
stats from pool_all.csv for the "gap he fills" chart.

Run AFTER 03 and 04:  python scraping/05_scrape_club_role.py
"""

import csv

from sofascore import (
    COMPARE_CLUB,
    DATA_RAW,
    PLAYER_POSITION,
    ROLE_CODES,
    ROLE_LABEL,
    SofascoreClient,
    fetch_characteristics,
    load_characteristics_cache,
    output_exists,
    write_csv,
)


def main() -> None:
    if output_exists("club_role.csv"):
        return

    with open(DATA_RAW / "squads.csv", encoding="utf-8") as fh:
        squads = list(csv.DictReader(fh))

    club = [r for r in squads
            if COMPARE_CLUB.lower() in (r.get("team_name") or "").lower()
            and r.get("position") == PLAYER_POSITION]
    if not club:
        teams = sorted({r.get("team_name") for r in squads})
        raise SystemExit(
            f"No position-{PLAYER_POSITION} players found for {COMPARE_CLUB!r}. "
            f"Team names in squads.csv include: {teams[:30]}"
        )
    print(f"{COMPARE_CLUB}: {len(club)} position-{PLAYER_POSITION} players in squad")

    cache = load_characteristics_cache()
    fetch_characteristics(SofascoreClient(), {r["player_id"] for r in club}, cache)

    rows = []
    for player in club:
        positions = cache.get(player["player_id"], "")
        is_role = bool(ROLE_CODES & set(positions.split("|"))) if positions else False
        print(f"  {player['player_name']:24s} {positions or '(unknown)'}"
              f"{'  -> ' + ROLE_LABEL if is_role else ''}")
        rows.append({
            "player_id": player["player_id"],
            "player_name": player["player_name"],
            "team_name": player["team_name"],
            "birth_date": player.get("birth_date"),
            "positions_detail": positions,
            "is_role": str(is_role),
        })

    n_role = sum(1 for r in rows if r["is_role"] == "True")
    if n_role == 0:
        print(f"WARNING: no {ROLE_LABEL} tagged - the R chart will fall back "
              f"to all {COMPARE_CLUB} position-{PLAYER_POSITION} players")
    write_csv(rows, "club_role.csv")


if __name__ == "__main__":
    main()
