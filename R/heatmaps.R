# heatmaps.R ------------------------------------------------------------------
# Ahanor's pitch heatmaps from the scraped Sofascore coordinates.
#
# Reads  data/raw/season_heatmaps.csv   season-aggregate point clouds
#        data/raw/heatmap_points.csv    per-match point clouds
# Writes figures/heatmap_seasons.png    Serie A, 24/25 vs 25/26 side by side
#        figures/heatmap_2526_all.png   25/26 all competitions, one pitch
#
# Run:  Rscript R/heatmaps.R
#
# Coordinates are Sofascore's 0-100 x 0-100 space, attacking left -> right.
# Points carry a count weight; tidyr::uncount() expands them so the kernel
# density estimate is weighted correctly.

source("R/viz_common.R")

# ---- titles: edit freely, nothing else depends on the wording ---------------
TITLE_SEASONS   <- "Genoa to Bergamo"
TITLE_FOOTPRINT <- "The 2025-26 Footprint"

CAPTION <- chart_footer("Sofascore 0-100 pitch coordinates")

# heat_layers() / pitch_plot() / MT_SURFACE come from viz_common.R

dir.create("figures", showWarnings = FALSE)

# ---- 1. Serie A season heatmaps, side by side -------------------------------
seasons <- readr::read_csv("data/raw/season_heatmaps.csv", show_col_types = FALSE) |>
  filter(tournament == "Serie A") |>
  mutate(season_label = paste0(
    ifelse(season_name == CURRENT_SEASON, "25/26 - Atalanta", paste0(season_name, " - Genoa"))
  )) |>
  uncount(weights = pmax(1, round(count)))

if (nrow(seasons) == 0) stop("no Serie A rows in season_heatmaps.csv")

p1 <- pitch_plot(
  seasons,
  TITLE_SEASONS,
  "Honest Ahanor's Serie A heatmaps, season by season",
  CAPTION
) +
  facet_wrap(~season_label, ncol = 2)

save_fig("figures/heatmap_seasons.png", p1, width = 11, height = 5.4,
         bg = MT_SURFACE)

# ---- 2. 25/26 all competitions, from per-match points -----------------------
matches <- readr::read_csv("data/raw/heatmap_points.csv", show_col_types = FALSE) |>
  filter(date >= as.Date("2025-07-01")) |>
  uncount(weights = pmax(1, round(count)))

if (nrow(matches) > 0) {
  n_matches <- length(unique(matches$event_id))
  p2 <- pitch_plot(
    matches,
    TITLE_FOOTPRINT,
    paste0("Honest Ahanor, all competitions - aggregated from ",
           n_matches, " matches"),
    CAPTION
  )
  save_fig("figures/heatmap_2526_all.png", p2, width = 8, height = 6.4,
           bg = MT_SURFACE)
} else {
  message("no 25/26 rows in heatmap_points.csv - skipped all-competitions map")
}
