"""Join the Big-5 raw data into the analysis-ready comparison pool.

Steps:
  1. join peer_stats.csv (per-season stats) with squads.csv (birth dates)
     on player_id
  2. compute age at each row's own season end (SEASONS) and per-90 versions
     of the count stats
  3. filter: PLAYER_POSITION, age < AGE_MAX at that season's end, minutes >=
     MIN_MINUTES (the subject's own rows are always kept)
  4. enrich: fetch each pool player's detailed positions (the one endpoint
     that separates e.g. full-back from centre-back; the leaderboard only
     says 'D') -> is_role column (ROLE_CODES). Best-effort: if the endpoint
     misbehaves, is_role stays empty and the pool is "all young <position>"
     - the R side falls back accordingly.

Outputs (data/raw/):
  characteristics.csv   player_id -> detailed positions cache (one network
                        call per pool player, ~1 request/1.5s; cached, so
                        re-runs are instant)
  pool_all.csv          same-position pool, any age (percentile scale for
                        the club comparison and the left-footed scatter)
  pool_u23.csv          the deliverable: one row per player with bio,
                        league, raw + per-90 stats, age, is_role

Run AFTER 01 and 03:  python scraping/04_build_pool.py
"""

import csv
from datetime import date

from sofascore import (
    AGE_MAX,
    DATA_RAW,
    MIN_MINUTES,
    PLAYER_NAME,
    PLAYER_POSITION,
    ROLE_CODES,
    SEASONS,
    SofascoreClient,
    fetch_characteristics,
    load_characteristics_cache,
    output_exists,
    subject_id,
    write_csv,
)

# Count stats that get a _per90 twin (rates/percentages don't).
PER90_FIELDS = [
    "goals", "assists", "expectedAssists", "tackles", "interceptions",
    "clearances", "ballRecovery", "blockedShots",
    "totalDuelsWon", "groundDuelsWon", "aerialDuelsWon",
    "accuratePasses", "accurateLongBalls", "keyPasses",
    "bigChancesCreated", "successfulDribbles",
    "possessionLost", "fouls", "wasFouled",
]

def read_csv(filename: str) -> list[dict]:
    with open(DATA_RAW / filename, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def build_pool(player_id: int, apply_age_filter: bool = True) -> list[dict]:
    stats = read_csv("peer_stats.csv")
    if stats and "season" not in stats[0]:
        raise SystemExit(
            "peer_stats.csv has no 'season' column - it predates the "
            "two-season scrape. Re-run: python scraping/03_scrape_peer_pool.py"
        )
    squads = {row["player_id"]: row for row in read_csv("squads.csv")}

    pool = []
    for row in stats:
        # age is measured against the END of the row's own season, so the
        # 24/25 pool is "U23 as of June 2025" and 25/26 "U23 as of June 2026"
        reference = SEASONS.get(row.get("season"))
        if reference is None:
            continue
        bio = squads.get(row["player_id"])
        is_subject = row["player_id"] == str(player_id)
        if not bio or not bio.get("birth_date"):
            if not is_subject:
                continue
            bio = bio or {}
        birth = date.fromisoformat(bio["birth_date"]) if bio.get("birth_date") else None
        age = (reference - birth).days / 365.25 if birth else None

        # position comes from the SQUAD data - the leaderboard's player
        # object carries no position field (observed empty on real data)
        position = bio.get("position") or row.get("position") or (
            PLAYER_POSITION if is_subject else None
        )

        # the subject's own rows always survive - the R side needs him in
        # every season even where he misses a filter (minutes, or a squad
        # row that vanished after a transfer)
        minutes = to_float(row.get("minutesPlayed"))
        if not is_subject:
            if position != PLAYER_POSITION:
                continue
            if apply_age_filter and (age is None or age >= AGE_MAX):
                continue
            if not minutes or minutes < MIN_MINUTES:
                continue

        merged = {
            **row,
            "position": position,
            "birth_date": bio.get("birth_date"),
            "age": round(age, 2) if age is not None else None,
            "height_cm": bio.get("height_cm"),
            "preferred_foot": bio.get("preferred_foot"),
        }
        for field in PER90_FIELDS:
            value = to_float(row.get(field))
            merged[f"{field}_per90"] = (
                round(value / minutes * 90, 3)
                if value is not None and minutes else None
            )
        pool.append(merged)
    return pool


def enrich_positions(pool: list[dict]) -> None:
    """Add is_role via /player/{id}/characteristics (cached in characteristics.csv)."""
    cache = load_characteristics_cache()
    fetch_characteristics(SofascoreClient(), {p["player_id"] for p in pool}, cache)

    for player in pool:
        positions = cache.get(player["player_id"], "")
        player["positions_detail"] = positions
        player["is_role"] = (
            "" if not positions
            else str(bool(ROLE_CODES & set(positions.split("|"))))
        )


def main() -> None:
    player_id = subject_id()  # offline: 01 cached it (or PLAYER_ID is set)

    # all-ages same-position pool: the common percentile scale for the club
    # comparison chart (no age filter, no role enrichment needed)
    if not output_exists("pool_all.csv"):
        all_pool = build_pool(player_id, apply_age_filter=False)
        print(f"all-ages pool: {len(all_pool)} players (position {PLAYER_POSITION})")
        write_csv(all_pool, "pool_all.csv")

    if output_exists("pool_u23.csv"):
        return
    pool = build_pool(player_id)
    print(f"pool after age/position/minutes filter: {len(pool)} players")
    if not pool:
        raise SystemExit("Empty pool - check peer_stats.csv/squads.csv and filters")

    for season in SEASONS:
        if not any(p["player_id"] == str(player_id) and p.get("season") == season
                   for p in pool):
            print(f"NOTE: {PLAYER_NAME} has no {season} row (not ranked on that "
                  "season's leaderboard?) - the R charts will show that "
                  "season without him.")

    enrich_positions(pool)
    n_role = sum(1 for p in pool if p["is_role"] == "True")
    print(f"tagged {n_role} same-role players ({ROLE_CODES}) "
          f"({sum(1 for p in pool if p['is_role'] == '')} unknown)")
    write_csv(pool, "pool_u23.csv")


if __name__ == "__main__":
    main()
