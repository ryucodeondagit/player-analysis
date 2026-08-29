"""Diagnose why 04_build_pool.py yields a small/empty pool.

Replays build_pool's filter stage by stage against the real CSVs and prints
how many rows survive each stage, plus the actual values seen in the fields
the filters depend on.

Run:  python scraping/diagnose.py
"""

import csv
from collections import Counter
from datetime import date

from sofascore import AGE_MAX, DATA_RAW, MIN_MINUTES, SEASONS


def read(name):
    with open(DATA_RAW / name, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


stats = read("peer_stats.csv")
squads = {row["player_id"]: row for row in read("squads.csv")}

print(f"peer_stats rows: {len(stats)}")
print(f"squad players:   {len(squads)}")
print(f"seasons seen:    {Counter(r.get('season') for r in stats)}")
print(f"positions seen:  {Counter(r.get('position') for r in stats)}")

nonempty_minutes = sum(1 for r in stats if (r.get("minutesPlayed") or "").strip())
print(f"rows with minutesPlayed: {nonempty_minutes}")
nonempty_birth = sum(1 for r in squads.values() if (r.get("birth_date") or "").strip())
print(f"squad rows with birth_date: {nonempty_birth}")

stage = Counter()
ages = []
for row in stats:
    reference = SEASONS.get(row.get("season"))
    if reference is None:
        stage["dropped: unknown season"] += 1
        continue
    bio = squads.get(row["player_id"])
    if not bio:
        stage["dropped: no squad row (left the league?)"] += 1
        continue
    if not (bio.get("birth_date") or "").strip():
        stage["dropped: squad row lacks birth_date"] += 1
        continue
    age = (reference - date.fromisoformat(bio["birth_date"])).days / 365.25
    if row.get("position") != "D":
        stage["dropped: position != 'D'"] += 1
        continue
    ages.append(age)
    if age >= AGE_MAX:
        stage[f"dropped: age >= {AGE_MAX}"] += 1
        continue
    try:
        minutes = float(row.get("minutesPlayed") or 0)
    except ValueError:
        minutes = 0
    if minutes < MIN_MINUTES:
        stage[f"dropped: minutes < {MIN_MINUTES}"] += 1
        continue
    stage["SURVIVED"] += 1

print("\nfilter stages:")
for name, count in stage.most_common():
    print(f"  {count:6d}  {name}")

if ages:
    young = sum(1 for a in ages if a < AGE_MAX)
    print(f"\ndefenders with known age: {len(ages)}, under {AGE_MAX}: {young}")

print("\nsample stats row:")
sample = stats[0]
for key in ("player_id", "player_name", "position", "season", "league",
            "minutesPlayed", "rating", "tackles"):
    print(f"  {key} = {sample.get(key)!r}")
