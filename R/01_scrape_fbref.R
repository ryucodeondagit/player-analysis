# 01_scrape_fbref.R -----------------------------------------------------------
# Scrapes everything we need from FBref via worldfootballR:
#
#   1. Ahanor's season-by-season stats (standard / defense / passing /
#      possession / misc) ................................. fbref_player_seasons
#   2. Ahanor's per-match logs for 2024-25 and 2025-26 .... fbref_match_logs
#   3. FBref's own scouting-report percentiles vs positional
#      peers (raw material for a pizza/radar chart) ....... fbref_scouting_report
#   4. Every Big-5-league player's advanced season stats,
#      incl. Age — the pool we filter later to build the
#      "vs his age range" comparison ...................... fbref_big5_<stat>
#
# Run:  Rscript R/01_scrape_fbref.R      (takes several minutes: ~20 FBref
#                                         requests x 7s pause, by design)
#
# worldfootballR is doing classic rvest HTML-table scraping underneath —
# including un-commenting the tables FBref hides inside HTML comments, which
# is the main reason to use the package instead of raw rvest.

source("R/00_setup.R")
library(worldfootballR)

# Stat pages that exist for an outfield defender. ("shooting"/"gca" add little
# for a fullback with 0 goals; add them here later if you want them.)
PLAYER_STAT_TYPES <- c("standard", "defense", "passing", "possession", "misc")

# ---- 1. season-by-season stats ----------------------------------------------
for (st in PLAYER_STAT_TYPES) {
  name <- paste0("fbref_player_seasons_", st)
  if (raw_exists(name)) { message("skip (cached): ", name); next }

  df <- fb_player_season_stats(FBREF_PLAYER_URL, stat_type = st)
  save_raw(df, name)
  polite_pause()
}

# ---- 2. per-match logs -------------------------------------------------------
# "summary" carries minutes, touches, tackles, cards etc. per match — enough
# for form-over-time charts. Add stat_type "defense"/"passing" later if the
# viz needs finer per-match detail.
for (yr in SEASON_END_YEARS) {
  name <- paste0("fbref_match_logs_", yr)
  if (raw_exists(name)) { message("skip (cached): ", name); next }

  df <- fb_player_match_logs(
    FBREF_PLAYER_URL,
    season_end_year = yr,
    stat_type = "summary"
  )
  save_raw(df, name)
  polite_pause()
}

# ---- 3. FBref scouting report (percentiles vs positional peers) -------------
# pos_versus = "primary" compares him against players sharing his primary
# position across the Big 5 leagues over the last 365 days. This table is
# already in per-90 + percentile form — ideal for a pizza chart.
if (!raw_exists("fbref_scouting_report")) {
  scout <- fb_player_scouting_report(
    FBREF_PLAYER_URL,
    pos_versus = "primary",
    time_pause = FBREF_PAUSE_SECONDS
  )
  save_raw(scout, "fbref_scouting_report")
  polite_pause()
} else {
  message("skip (cached): fbref_scouting_report")
}

# ---- 4. Big-5 player pool (for the age-range comparison) --------------------
# One request per stat type; each returns EVERY player in the Big 5 leagues
# for 2025-26 with Age and Born columns. 03_build_peer_pool.R filters this to
# young defenders with real minutes and computes percentiles — we deliberately
# scrape broad here and filter later, so changing the age cutoff (U19 vs U21)
# never requires re-scraping.
for (st in PLAYER_STAT_TYPES) {
  name <- paste0("fbref_big5_", st)
  if (raw_exists(name)) { message("skip (cached): ", name); next }

  df <- fb_big5_advanced_season_stats(
    season_end_year = max(SEASON_END_YEARS),
    stat_type = st,
    team_or_player = "player"
  )
  save_raw(df, name)
  polite_pause()
}

# "playing_time" gives reliable minutes for the minutes-played filter
# (the "standard" table has minutes too, but this one is canonical).
if (!raw_exists("fbref_big5_playing_time")) {
  df <- fb_big5_advanced_season_stats(
    season_end_year = max(SEASON_END_YEARS),
    stat_type = "playing_time",
    team_or_player = "player"
  )
  save_raw(df, "fbref_big5_playing_time")
} else {
  message("skip (cached): fbref_big5_playing_time")
}

message("FBref scrape complete. Raw files in ", DATA_RAW, "/")
