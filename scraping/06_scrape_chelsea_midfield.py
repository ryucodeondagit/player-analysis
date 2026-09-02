"""Scrape the Chelsea midfield roster (MIDFIELD_ROSTER in sofascore.py).

The question is squad-level - "does the midfield survive without Enzo?" -
so this pulls the SAME evidence for every name on the roster: who they are,
which 25/26 league season counts as their evidence, that season's stats,
and that season's heatmap.

Steps:
  1. resolve each roster name to a Sofascore id: MIDFIELD_PLAYER_IDS
     override, else Chelsea's current squad, else Sofascore search (the
     departed player only resolves through search - he is at another club)
  2. per player: list their stats seasons, pick the MIDFIELD_SEASON row
     (Premier League preferred, any Big-5 league otherwise - a new signing
     bought from abroad brings his own league's season)
  3. per player: that season's flat stats + season-aggregate heatmap
  4. make sure the Premier League MIDFIELD_SEASON leaderboard + squads
     caches exist (reuses 03's functions) - 07 builds the pool from them

Outputs (data/raw/):
  chelsea_midfield.csv           roster: ids, role, evidence (tournament,
                                 season), current team. player_name is the
                                 short config name (charts), sofascore_name
                                 the long form Sofascore prints
  chelsea_midfield_stats.csv     one row per player: full flat stats block
  chelsea_midfield_heatmaps.csv  (x, y, count) points per player
  peer_stats_premier-league_25-26.csv, squads_premier-league.csv
                                 (only if missing - 03's cache files)

Run:  python scraping/06_scrape_chelsea_midfield.py
"""

import csv

from sofascore import (
    BIG5_LEAGUES,
    CHELSEA_TEAM_ID,
    DATA_RAW,
    MIDFIELD_PLAYER_IDS,
    MIDFIELD_ROSTER,
    MIDFIELD_SEASON,
    PREMIER_LEAGUE_ID,
    SofascoreClient,
    import_script,
    names_match,
    output_exists,
    parse_heatmap,
    parse_search_players,
    parse_season_stats,
    parse_squad,
    parse_statistics_seasons,
    pick_season_row,
    write_csv,
)


def resolve_roster(client: SofascoreClient) -> list[dict]:
    """One row per roster name with its Sofascore id (or a loud failure)."""
    body = client.get("team", CHELSEA_TEAM_ID, "players", ok404=True)
    squad = parse_squad(body, CHELSEA_TEAM_ID, "Chelsea")
    if not squad:
        raise SystemExit("Chelsea squad came back empty - check CHELSEA_TEAM_ID")
    mids = [p["player_name"] for p in squad if p.get("position") == "M"]
    print(f"Chelsea squad: {len(squad)} players; midfielders listed by "
          f"Sofascore: {', '.join(mids)}")

    rows = []
    unresolved = []
    for name, role in MIDFIELD_ROSTER.items():
        hit = None
        source = ""
        if name in MIDFIELD_PLAYER_IDS:
            hit = {"player_id": MIDFIELD_PLAYER_IDS[name], "player_name": name,
                   "team_name": None}
            source = "override"
        if hit is None:
            squad_hits = [p for p in squad if names_match(name, p["player_name"])]
            if squad_hits:
                hit = {**squad_hits[0], "team_name": "Chelsea"}
                source = "squad"
        if hit is None:
            body = client.get("search", "all", params={"q": name, "page": 0},
                              ok404=True)
            search_hits = [p for p in parse_search_players(body)
                           if names_match(name, p["player_name"])]
            if search_hits:
                hit = search_hits[0]  # search ranks by relevance
                source = "search"
                if len(search_hits) > 1:
                    print(f"  NOTE: {len(search_hits)} search hits for {name!r}; "
                          f"took {hit['player_name']} ({hit['team_name']}). "
                          "Pin MIDFIELD_PLAYER_IDS if that is the wrong one.")
        if hit is None:
            unresolved.append(name)
            continue
        print(f"  {name:20s} -> {hit['player_id']}  {hit['player_name']}"
              f"  [{hit.get('team_name') or '?'}]  via {source}")
        rows.append({
            "player_id": hit["player_id"],
            "player_name": name,                    # short form, used on charts
            "sofascore_name": hit["player_name"],   # as Sofascore prints it
            "config_name": name,
            "role": role,
            "current_team": hit.get("team_name"),
            "resolved_via": source,
        })
    if unresolved:
        raise SystemExit(
            f"Could not resolve {unresolved}. Look each one up on "
            "sofascore.com and add the id to MIDFIELD_PLAYER_IDS in "
            "scraping/sofascore.py"
        )
    return rows


def attach_evidence_season(client: SofascoreClient, roster: list[dict]) -> None:
    """Add the (tournament, season) that is each player's MIDFIELD_SEASON evidence."""
    for row in roster:
        body = client.get("player", row["player_id"], "statistics", "seasons",
                          ok404=True)
        seasons = parse_statistics_seasons(body)
        pick = pick_season_row(seasons, MIDFIELD_SEASON, PREMIER_LEAGUE_ID,
                               BIG5_LEAGUES.values())
        if pick is None:
            available = sorted({s.get("season_name") for s in seasons})[-4:]
            print(f"  WARNING: {row['player_name']} has no {MIDFIELD_SEASON} "
                  f"stats (has {available}) - he will be missing from the charts")
            row.update(tournament_id=None, tournament=None, season_id=None,
                       season_name=None)
            continue
        print(f"  {row['player_name']:24s} evidence: {pick['tournament']} "
              f"{pick['season_name']}")
        row.update(
            tournament_id=pick["tournament_id"], tournament=pick["tournament"],
            season_id=pick["season_id"], season_name=pick["season_name"],
        )


def read_roster() -> list[dict]:
    with open(DATA_RAW / "chelsea_midfield.csv", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def main() -> None:
    client = SofascoreClient()

    # ---- 1 + 2: roster -> ids -> evidence season -----------------------------
    if not output_exists("chelsea_midfield.csv"):
        roster = resolve_roster(client)
        attach_evidence_season(client, roster)
        write_csv(roster, "chelsea_midfield.csv")
    roster = [r for r in read_roster() if r.get("season_id")]

    # ---- 3a: season stats ----------------------------------------------------
    if not output_exists("chelsea_midfield_stats.csv"):
        rows = []
        for player in roster:
            body = client.get(
                "player", player["player_id"],
                "unique-tournament", player["tournament_id"],
                "season", player["season_id"],
                "statistics", "overall", ok404=True,
            )
            stats = parse_season_stats(body)
            print(f"stats {player['player_name']}: "
                  f"{stats.get('minutesPlayed', '?')} min, "
                  f"{stats.get('keyPasses', '?')} key passes, "
                  f"{stats.get('assists', '?')} assists")
            if not stats:
                print("  (no stats - skipped)")
                continue
            rows.append({**player, **stats})
        write_csv(rows, "chelsea_midfield_stats.csv")

    # ---- 3b: season heatmaps -------------------------------------------------
    if not output_exists("chelsea_midfield_heatmaps.csv"):
        rows = []
        for player in roster:
            body = client.get(
                "player", player["player_id"],
                "unique-tournament", player["tournament_id"],
                "season", player["season_id"],
                "heatmap", "overall", ok404=True,
            )
            points = parse_heatmap(body)
            print(f"heatmap {player['player_name']}: {len(points)} points")
            for point in points:
                rows.append({
                    "player_id": player["player_id"],
                    "player_name": player["player_name"],
                    "role": player["role"],
                    "tournament": player["tournament"],
                    **point,
                })
        write_csv(rows, "chelsea_midfield_heatmaps.csv")

    # ---- 4: Premier League pool caches (03's files, 03's functions) ----------
    peer = import_script("03_scrape_peer_pool")
    season_slug = MIDFIELD_SEASON.replace("/", "-")
    stats_file = f"peer_stats_premier-league_{season_slug}.csv"
    squad_file = "squads_premier-league.csv"
    if not output_exists(stats_file) or not output_exists(squad_file):
        season_id = peer.find_season_id(client, PREMIER_LEAGUE_ID,
                                        "premier-league", MIDFIELD_SEASON)
        if not (DATA_RAW / stats_file).exists():
            rows = peer.fetch_leaderboard(client, PREMIER_LEAGUE_ID, season_id)
            for row in rows:
                row["league"] = "premier-league"
                row["season"] = MIDFIELD_SEASON
            write_csv(rows, stats_file)
        if not (DATA_RAW / squad_file).exists():
            rows = peer.fetch_squads(client, PREMIER_LEAGUE_ID, season_id)
            for row in rows:
                row["league"] = "premier-league"
            write_csv(rows, squad_file)
    print("done - next: python scraping/07_build_midfield_pool.py")


if __name__ == "__main__":
    main()
