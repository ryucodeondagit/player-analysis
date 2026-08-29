# 00_setup.R ------------------------------------------------------------------
# Shared constants and helpers for the Honest Ahanor analysis.
# Every other script begins with: source("R/00_setup.R")

# ---- packages ----------------------------------------------------------------
# worldfootballR : FBref / Transfermarkt scraping (rvest under the hood)
# httr2, jsonlite: raw JSON endpoint calls (Sofascore)
# dplyr, purrr, tidyr, readr: data wrangling + IO
required_pkgs <- c(
  "worldfootballR", "httr2", "jsonlite",
  "dplyr", "purrr", "tidyr", "readr", "tibble"
)
to_install <- setdiff(required_pkgs, rownames(installed.packages()))
if (length(to_install) > 0) install.packages(to_install)

library(dplyr)
library(purrr)

# ---- player / competition constants -----------------------------------------
PLAYER_NAME <- "Honest Ahanor"

# FBref player id 42ff58c3 -> https://fbref.com/en/players/42ff58c3/Honest-Ahanor
FBREF_PLAYER_URL <- "https://fbref.com/en/players/42ff58c3/Honest-Ahanor"

# Sofascore ids. The player id is visible in his profile URL:
# https://www.sofascore.com/football/player/honest-ahanor/1634980
SOFASCORE_PLAYER_ID <- 1634980
SOFASCORE_SERIE_A_UNIQUE_TOURNAMENT_ID <- 23 # Sofascore's id for Serie A

# Seasons of interest, FBref-style "season end year":
#   2025 = 2024-25 (breakout at Genoa), 2026 = 2025-26 (first Atalanta season)
SEASON_END_YEARS <- c(2025, 2026)

# Only fetch Sofascore matches on/after this date (start of 2025-26 pre-season).
# Widen it to "2024-07-01" if you also want Genoa-era heatmaps.
SOFASCORE_CUTOFF_DATE <- as.Date("2025-08-01")

# ---- paths -------------------------------------------------------------------
DATA_RAW <- "data/raw"
dir.create(DATA_RAW, recursive = TRUE, showWarnings = FALSE)

# ---- caching helpers ---------------------------------------------------------
# Scraping etiquette: hit each source once, then work from disk. Every scrape
# script checks raw_exists() first and skips work already on disk.
# Re-scrape by deleting files in data/raw/ or running with FORCE_REFRESH=1:
#   FORCE_REFRESH=1 Rscript R/01_scrape_fbref.R
FORCE_REFRESH <- identical(Sys.getenv("FORCE_REFRESH"), "1")

raw_path <- function(name) file.path(DATA_RAW, paste0(name, ".rds"))

raw_exists <- function(name) !FORCE_REFRESH && file.exists(raw_path(name))

save_raw <- function(df, name) {
  saveRDS(df, raw_path(name))
  # CSV twin for eyeballing outside R; .rds stays the source of truth
  # (CSV round-trips lose column types).
  try(readr::write_csv(df, file.path(DATA_RAW, paste0(name, ".csv"))), silent = TRUE)
  message(sprintf("saved %s (%d rows)", raw_path(name), nrow(df)))
  invisible(df)
}

read_raw <- function(name) readRDS(raw_path(name))

# ---- polite scraping ---------------------------------------------------------
# FBref temp-bans IPs that exceed ~10 requests/min, and worldfootballR's own
# built-in pauses assume you don't stack calls back-to-back. One generous pause
# between every FBref call keeps you comfortably inside the limit.
FBREF_PAUSE_SECONDS <- 7

polite_pause <- function(seconds = FBREF_PAUSE_SECONDS) {
  Sys.sleep(seconds)
}
