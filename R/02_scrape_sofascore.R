# 02_scrape_sofascore.R -------------------------------------------------------
# Pulls the raw material for heatmaps from Sofascore's (unofficial) JSON API —
# the same endpoints the sofascore.com frontend calls. FBref has no coordinate
# data at all, so this is the practical open source for touch heatmaps.
#
#   1. Page through the player's recent matches ......... sofascore_matches
#   2. For each finished match since the cutoff date,
#      fetch his per-match heatmap point cloud .......... sofascore_heatmap_points
#
# Output: one long data frame of (x, y, count) points in Sofascore's 0-100
# pitch space, tagged with match metadata — ready for ggsoccer +
# stat_density_2d, aggregated over the season or faceted per match.
#
# Run:  Rscript R/02_scrape_sofascore.R
#
# CAVEATS — read before running:
# * Unofficial endpoint: fine for a personal project at this volume (a few
#   dozen requests), but it is technically against Sofascore's ToS, can change
#   shape without notice, and must not be hammered. Keep the throttle.
# * Requests without a browser-like User-Agent get 403'd.
# * A 404 on a heatmap simply means no data for that player+match (unused sub,
#   or a competition Sofascore doesn't track positions for) — not an error.

source("R/00_setup.R")
library(httr2)

SOFASCORE_BASE <- "https://api.sofascore.com/api/v1"

# ---- request helper ----------------------------------------------------------
# One place for headers / throttle / retry so every call behaves identically.
# req_throttle caps us at ~12 requests/min; req_retry handles transient 5xx.
ss_request <- function(...) {
  request(SOFASCORE_BASE) |>
    req_url_path_append(...) |>
    req_user_agent(paste(
      "Mozilla/5.0 (X11; Linux x86_64; rv:132.0)",
      "Gecko/20100101 Firefox/132.0"
    )) |>
    req_headers(Accept = "application/json") |>
    # capacity/fill_time_s needs httr2 >= 1.1.0; on older httr2 use
    # req_throttle(rate = 12 / 60) instead.
    req_throttle(capacity = 12, fill_time_s = 60) |>
    req_retry(max_tries = 3)
}

# Perform a request; return parsed JSON, or NULL on 404 (= "no data here").
ss_fetch <- function(req) {
  resp <- tryCatch(
    req_perform(req),
    httr2_http_404 = function(cnd) NULL
  )
  if (is.null(resp)) return(NULL)
  resp_body_json(resp)
}

# ---- 1. the player's matches -------------------------------------------------
# /player/{id}/events/last/{page} pages backwards through his played matches
# (page 0 = most recent). We walk pages until we're past the cutoff date.
fetch_player_matches <- function(player_id, cutoff_date) {
  all_events <- list()
  page <- 0
  repeat {
    body <- ss_fetch(ss_request("player", player_id, "events", "last", page))
    if (is.null(body) || length(body$events) == 0) break

    all_events <- c(all_events, body$events)

    # Stop paging once the oldest event on this page predates the cutoff —
    # everything on later pages is older still.
    oldest <- min(map_dbl(body$events, "startTimestamp"))
    if (as.Date(as.POSIXct(oldest, origin = "1970-01-01", tz = "UTC")) < cutoff_date) break
    if (!isTRUE(body$hasNextPage)) break
    page <- page + 1
  }

  # Flatten the fields we care about. pluck() with a .default survives events
  # that are missing a field (e.g. friendlies without a uniqueTournament).
  map_dfr(all_events, function(ev) {
    tibble::tibble(
      event_id   = ev$id,
      date       = as.Date(as.POSIXct(ev$startTimestamp, origin = "1970-01-01", tz = "UTC")),
      tournament = pluck(ev, "tournament", "uniqueTournament", "name", .default = NA_character_),
      tournament_id = pluck(ev, "tournament", "uniqueTournament", "id", .default = NA_integer_),
      home_team  = pluck(ev, "homeTeam", "name", .default = NA_character_),
      away_team  = pluck(ev, "awayTeam", "name", .default = NA_character_),
      status     = pluck(ev, "status", "type", .default = NA_character_)
    )
  }) |>
    distinct(event_id, .keep_all = TRUE) |>
    arrange(date)
}

if (raw_exists("sofascore_matches")) {
  matches <- read_raw("sofascore_matches")
  message("skip (cached): sofascore_matches")
} else {
  matches <- fetch_player_matches(SOFASCORE_PLAYER_ID, SOFASCORE_CUTOFF_DATE)
  save_raw(matches, "sofascore_matches")
}

# Keep finished matches since the cutoff. Not filtered to Serie A only —
# Coppa Italia / European minutes are part of the picture; the tournament
# column lets you facet or filter at plot time.
target_matches <- matches |>
  filter(status == "finished", date >= SOFASCORE_CUTOFF_DATE)

message(sprintf("%d finished matches since %s", nrow(target_matches), SOFASCORE_CUTOFF_DATE))

# ---- 2. per-match heatmaps ---------------------------------------------------
# /event/{eventId}/player/{playerId}/heatmap returns his touch/position point
# cloud for that match in a 0-100 x 0-100 pitch space.
#
# NOTE: the point list has been observed under the key "heatmap" and, on some
# API versions, "points"; and points sometimes carry a "count" weight and
# sometimes don't. parse_heatmap() accepts all of these — if a first local run
# yields 0 points for every match, print one raw `body` and check what the
# key is called today.
parse_heatmap <- function(body) {
  pts <- body$heatmap %||% body$points
  if (is.null(pts) || length(pts) == 0) return(NULL)
  map_dfr(pts, function(p) {
    tibble::tibble(
      x     = pluck(p, "x", .default = NA_real_),
      y     = pluck(p, "y", .default = NA_real_),
      count = pluck(p, "count", .default = 1) # unweighted point clouds -> weight 1
    )
  })
}

fetch_match_heatmap <- function(event_id, player_id) {
  body <- ss_fetch(ss_request("event", event_id, "player", player_id, "heatmap"))
  if (is.null(body)) return(NULL) # 404: no heatmap for this player+match
  parse_heatmap(body)
}

if (raw_exists("sofascore_heatmap_points")) {
  message("skip (cached): sofascore_heatmap_points")
  heatmap_points <- read_raw("sofascore_heatmap_points")
} else {
  heatmap_points <- pmap_dfr(
    list(target_matches$event_id, target_matches$date,
         target_matches$home_team, target_matches$away_team,
         target_matches$tournament),
    function(event_id, date, home_team, away_team, tournament) {
      message(sprintf("heatmap %s  %s vs %s", date, home_team, away_team))
      pts <- fetch_match_heatmap(event_id, SOFASCORE_PLAYER_ID)
      if (is.null(pts)) return(NULL)
      pts |>
        mutate(
          event_id = event_id, date = date, tournament = tournament,
          home_team = home_team, away_team = away_team,
          .before = 1
        )
    }
  )
  save_raw(heatmap_points, "sofascore_heatmap_points")
}

message(sprintf(
  "Sofascore scrape complete: %d heatmap points across %d matches.",
  nrow(heatmap_points), n_distinct(heatmap_points$event_id)
))
