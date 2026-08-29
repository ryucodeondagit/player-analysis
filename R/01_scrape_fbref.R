# 01_scrape_fbref.R -----------------------------------------------------------
# FBref data WITHOUT hitting fbref.com directly.
#
# FBref's bot protection (Cloudflare) now 403s scraper traffic, so the
# primary route here is worldfootballR's load_* functions: pre-scraped FBref
# tables downloaded from the maintainer's data releases on GitHub
# (JaseZiv/worldfootballR_data). No request ever touches fbref.com, so
# nothing can be blocked.
#
#   A. Big-5-league player tables for 2024-25 and 2025-26, all stat types.
#      This is BOTH the age-peer comparison pool AND the source of Ahanor's
#      own season lines (his rows are in these tables).
#   B. Ahanor's rows extracted from A into convenient per-player files.
#   C. Best-effort DIRECT scrapes (per-match logs, FBref scouting report).
#      These have no load_* equivalent, so they still need fbref.com and
#      will usually fail with HTTP 403. Failure is logged and skipped, never
#      fatal — if FBref ever unblocks you (different network, VPN), re-run
#      and they fill in.
#
# Run:  Rscript R/01_scrape_fbref.R   (or source("R/01_scrape_fbref.R"))

source("R/00_setup.R")
library(worldfootballR)

PLAYER_STAT_TYPES <- c(
  "standard", "defense", "passing", "possession", "misc", "playing_time"
)

# ---- A. Big-5 player tables from the pre-scraped data repo ------------------
for (yr in SEASON_END_YEARS) {
  for (st in PLAYER_STAT_TYPES) {
    name <- paste0("fbref_big5_", yr, "_", st)
    if (raw_exists(name)) { message("skip (cached): ", name); next }

    df <- load_fb_big5_advanced_season_stats(
      season_end_year = yr,
      stat_type = st,
      team_or_player = "player"
    )
    if (is.null(df) || nrow(df) == 0) {
      warning("empty result for ", name, " - data release may be lagging")
      next
    }
    save_raw(df, name)
    # GitHub releases, not FBref: a short courtesy pause is plenty.
    polite_pause(1)
  }
}

# ---- B. Ahanor's own season lines, extracted from the Big-5 tables ----------
# Matching on the FBref player id inside the Url column is robust to name
# variants ("Honest Ahanor" vs accent/ordering differences).
for (st in PLAYER_STAT_TYPES) {
  name <- paste0("fbref_player_seasons_", st)
  if (raw_exists(name)) { message("skip (cached): ", name); next }

  seasons <- map_dfr(SEASON_END_YEARS, function(yr) {
    big5 <- read_raw(paste0("fbref_big5_", yr, "_", st))
    url_col <- intersect(c("Url", "url"), names(big5))
    if (length(url_col) > 0) {
      big5 |> filter(grepl(FBREF_PLAYER_ID, .data[[url_col[1]]], fixed = TRUE))
    } else {
      # fall back to name matching if the data release drops the Url column
      big5 |> filter(.data[["Player"]] == PLAYER_NAME)
    }
  })

  if (nrow(seasons) == 0) {
    warning("no rows found for ", PLAYER_NAME, " in big5 ", st, " tables")
    next
  }
  save_raw(seasons, name)
}

# ---- C. best-effort direct FBref scrapes ------------------------------------
# Everything below talks to fbref.com and is expected to 403 on most
# connections. tryCatch keeps the script alive either way.
try_fbref <- function(what, expr) {
  result <- tryCatch(expr, error = function(e) {
    message(sprintf(
      "SKIPPED %s - direct FBref scrape failed (%s). Expected while FBref blocks scrapers; see README troubleshooting.",
      what, conditionMessage(e)
    ))
    NULL
  })
  invisible(result)
}

# Per-match logs (form-over-time). No load_* equivalent exists; the Sofascore
# script provides the per-match alternative when this is blocked.
for (yr in SEASON_END_YEARS) {
  name <- paste0("fbref_match_logs_", yr)
  if (raw_exists(name)) { message("skip (cached): ", name); next }

  try_fbref(name, {
    df <- fb_player_match_logs(
      FBREF_PLAYER_URL,
      season_end_year = yr,
      stat_type = "summary"
    )
    save_raw(df, name)
    polite_pause()
  })
}

# FBref's scouting-report percentiles. If this stays blocked we compute
# equivalent percentiles ourselves from the Big-5 pool in 03_build_peer_pool.R.
if (!raw_exists("fbref_scouting_report")) {
  try_fbref("fbref_scouting_report", {
    scout <- fb_player_scouting_report(
      FBREF_PLAYER_URL,
      pos_versus = "primary",
      time_pause = FBREF_PAUSE_SECONDS
    )
    save_raw(scout, "fbref_scouting_report")
  })
} else {
  message("skip (cached): fbref_scouting_report")
}

message("FBref data step complete. Raw files in ", DATA_RAW, "/")
