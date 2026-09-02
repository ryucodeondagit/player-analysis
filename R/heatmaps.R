# heatmaps.R ------------------------------------------------------------------
# The subject's pitch heatmaps from the scraped Sofascore coordinates.
#
# Reads  data/raw/season_heatmaps.csv   season-aggregate point clouds
#        data/raw/heatmap_points.csv    per-match point clouds
# Writes figures/heatmap_seasons.png    league seasons side by side (one
#                                       panel per league x season)
#        figures/heatmap_2526_all.png   25/26 all competitions, one pitch
#
# Run:  Rscript R/heatmaps.R
#
# Coordinates are Sofascore's 0-100 x 0-100 space, attacking left -> right.
# Points carry a count weight; tidyr::uncount() expands them so the kernel
# density estimate is weighted correctly.

source("R/viz_common.R")
require_subject()

# ---- titles: edit freely, nothing else depends on the wording ---------------
TITLE_SEASONS   <- paste0(SUBJECT_SHORT, ", Season by Season")
TITLE_FOOTPRINT <- "The 2025-26 Footprint"

# league seasons that get a panel (Sofascore's tournament names)
LEAGUES <- c("Premier League", "LaLiga", "Serie A", "Bundesliga", "Ligue 1")
SEASONS_IN_SCOPE <- SEASON_TEAMS  # names() = the seasons that get a panel

CAPTION <- chart_footer("Sofascore 0-100 pitch coordinates")

# heat_layers() / pitch_plot() / MT_SURFACE come from viz_common.R

dir.create("figures", showWarnings = FALSE)

# ---- 1. league season heatmaps, side by side --------------------------------
# One panel per (season, league): a loan move mid-season gives two panels
# for that season, which is the honest picture.
seasons <- readr::read_csv("data/raw/season_heatmaps.csv", show_col_types = FALSE) |>
  filter(tournament %in% LEAGUES, season_name %in% names(SEASONS_IN_SCOPE)) |>
  mutate(season_label = paste0(season_name, " - ", tournament)) |>
  arrange(season_name, tournament) |>
  mutate(season_label = factor(season_label, levels = unique(season_label))) |>
  uncount(weights = pmax(1, round(count)))

if (nrow(seasons) == 0) stop("no league rows in season_heatmaps.csv")
n_panels <- length(levels(droplevels(seasons$season_label)))

p1 <- pitch_plot(
  seasons,
  TITLE_SEASONS,
  paste0(PLAYER_NAME, "'s league heatmaps, season by season"),
  CAPTION
) +
  facet_wrap(~season_label, ncol = n_panels)

save_fig("figures/heatmap_seasons.png", p1, width = 4.3 * n_panels + 2.4,
         height = 5.4, bg = MT_SURFACE)

# ---- 2. 25/26 all competitions, from per-match points -----------------------
matches <- readr::read_csv("data/raw/heatmap_points.csv", show_col_types = FALSE) |>
  filter(date >= as.Date("2025-07-01")) |>
  uncount(weights = pmax(1, round(count)))

if (nrow(matches) > 0) {
  n_matches <- length(unique(matches$event_id))
  p2 <- pitch_plot(
    matches,
    TITLE_FOOTPRINT,
    paste0(PLAYER_NAME, ", all competitions - aggregated from ",
           n_matches, " matches"),
    CAPTION
  )
  save_fig("figures/heatmap_2526_all.png", p2, width = 8, height = 6.4,
           bg = MT_SURFACE)
} else {
  message("no 25/26 rows in heatmap_points.csv - skipped all-competitions map")
}
