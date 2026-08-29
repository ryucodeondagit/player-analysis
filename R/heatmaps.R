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

CAPTION <- "Data: Sofascore | 0-100 pitch space, attacking left to right"

# density surface: sequential blue, fading to transparent at the low end so
# the pitch shows through outside his active zones
heat_layers <- function() {
  list(
    stat_density_2d(
      geom = "polygon",
      aes(x = x, y = y, fill = after_stat(level), alpha = after_stat(level)),
      bins = 12, contour_var = "ndensity"
    ),
    scale_fill_gradient(low = COL_SEQ_LO, high = COL_SEQ_HI, guide = "none"),
    scale_alpha_continuous(range = c(0, 0.85), guide = "none")
  )
}

pitch_plot <- function(points, title, subtitle) {
  ggplot(points) +
    heat_layers() +
    pitch_layers() +
    coord_fixed(ratio = 68 / 105, xlim = c(0, 100), ylim = c(0, 100),
                expand = FALSE) +
    labs(title = title, subtitle = subtitle, caption = CAPTION) +
    theme_pitch()
}

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
  "Honest Ahanor - where he plays",
  "Serie A season heatmaps | left-sided defender, attacking left to right"
) +
  facet_wrap(~season_label, ncol = 2)

ggsave("figures/heatmap_seasons.png", p1, width = 11, height = 5, dpi = 150,
       bg = COL_SURFACE)
message("saved figures/heatmap_seasons.png")

# ---- 2. 25/26 all competitions, from per-match points -----------------------
matches <- readr::read_csv("data/raw/heatmap_points.csv", show_col_types = FALSE) |>
  filter(date >= as.Date("2025-07-01")) |>
  uncount(weights = pmax(1, round(count)))

if (nrow(matches) > 0) {
  n_matches <- length(unique(matches$event_id))
  p2 <- pitch_plot(
    matches,
    "Honest Ahanor - 2025-26, all competitions",
    paste0("Aggregated from ", n_matches, " matches (league + cups)")
  )
  ggsave("figures/heatmap_2526_all.png", p2, width = 8, height = 6, dpi = 150,
         bg = COL_SURFACE)
  message("saved figures/heatmap_2526_all.png")
} else {
  message("no 25/26 rows in heatmap_points.csv - skipped all-competitions map")
}
