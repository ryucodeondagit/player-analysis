"""Join the Big-5 raw data into the analysis-ready comparison pool.

Steps:
  1. join peer_stats.csv (season stats) with squads.csv (birth dates) on
     player_id
  2. compute age at REFERENCE_DATE and per-90 versions of the count stats
  3. filter: defenders, age < AGE_MAX, minutes >= MIN_MINUTES
  4. enrich: fetch each pool player's detailed positions (the one endpoint
     that knows CB vs full-back; the leaderboard only says 'D') -> is_cb
     column. Best-effort: if the endpoint misbehaves, is_cb stays empty and
     the pool is "all young defenders" - the R side falls back accordingly.

Outputs (data/raw/):
  characteristics.csv   player_id -> detailed positions cache (one network
                        call per pool player, ~1 request/1.5s; cached, so
                        re-runs are instant)
  pool_u23_defenders.csv  the deliverable: one row per player with bio,
                          league, raw + per-90 stats, age, is_cb

Run AFTER 03:  python scraping/04_build_pool.py
"""

import csv
from datetime import date

from sofascore import (
    AGE_MAX,
    DATA_RAW,
    MIN_MINUTES,
    PLAYER_ID,
    REFERENCE_DATE,
    SofascoreClient,
    output_exists,
    parse_characteristics,
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

CB_CODES = {"CB"}  # characteristics position codes counted as centre-back


def read_csv(filename: str) -> list[dict]:
    with open(DATA_RAW / filename, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def build_pool() -> list[dict]:
    stats = read_csv("peer_stats.csv")
    squads = {row["player_id"]: row for row in read_csv("squads.csv")}

    pool = []
    for row in stats:
        bio = squads.get(row["player_id"])
        if not bio or not bio.get("birth_date"):
            continue
        birth = date.fromisoformat(bio["birth_date"])
        age = (REFERENCE_DATE - birth).days / 365.25

        minutes = to_float(row.get("minutesPlayed"))
        if row.get("position") != "D":
            continue
        if age >= AGE_MAX or not minutes or minutes < MIN_MINUTES:
            continue

        merged = {
            **row,
            "birth_date": bio["birth_date"],
            "age": round(age, 2),
            "height_cm": bio.get("height_cm"),
            "preferred_foot": bio.get("preferred_foot"),
        }
        for field in PER90_FIELDS:
            value = to_float(row.get(field))
            merged[f"{field}_per90"] = (
                round(value / minutes * 90, 3) if value is not None else None
            )
        pool.append(merged)
    return pool


def enrich_positions(pool: list[dict]) -> None:
    """Add is_cb via /player/{id}/characteristics (cached in characteristics.csv)."""
    cache_path = DATA_RAW / "characteristics.csv"
    cache: dict[str, str] = {}
    if cache_path.exists():
        cache = {r["player_id"]: r["positions"] for r in read_csv("characteristics.csv")}

    client = SofascoreClient()
    missing = [p for p in pool if p["player_id"] not in cache]
    if missing:
        print(f"fetching detailed positions for {len(missing)} pool players "
              f"(~{len(missing) * 1.5 / 60:.0f} min)...")
    for i, player in enumerate(missing, 1):
        try:
            body = client.get("player", player["player_id"], "characteristics",
                              ok404=True)
            positions = parse_characteristics(body)
        except Exception as exc:  # noqa: BLE001 - enrichment must never kill the pool
            print(f"  characteristics failed for {player['player_name']}: {exc}")
            positions = []
        cache[player["player_id"]] = "|".join(positions)
        if i % 25 == 0:
            print(f"  {i}/{len(missing)}")

    write_csv(
        [{"player_id": pid, "positions": pos} for pid, pos in cache.items()],
        "characteristics.csv",
    )

    for player in pool:
        positions = cache.get(player["player_id"], "")
        player["positions_detail"] = positions
        player["is_cb"] = (
            "" if not positions
            else str(bool(CB_CODES & set(positions.split("|"))))
        )


def main() -> None:
    if output_exists("pool_u23_defenders.csv"):
        return
    pool = build_pool()
    print(f"pool after age/position/minutes filter: {len(pool)} defenders")
    if not pool:
        raise SystemExit("Empty pool - check peer_stats.csv/squads.csv and filters")

    if not any(p["player_id"] == str(PLAYER_ID) for p in pool):
        print("NOTE: Ahanor is not in the filtered pool (minutes below "
              f"{MIN_MINUTES}? position tag not 'D'?) - check his row in "
              "peer_stats.csv; the R side expects him present.")

    enrich_positions(pool)
    n_cb = sum(1 for p in pool if p["is_cb"] == "True")
    print(f"tagged {n_cb} centre-backs "
          f"({sum(1 for p in pool if p['is_cb'] == '')} unknown)")
    write_csv(pool, "pool_u23_defenders.csv")


if __name__ == "__main__":
    main()
