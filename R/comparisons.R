# comparisons.R ---------------------------------------------------------------
# Ahanor vs U23 Big-5 centre-backs, from the scraped pool.
#
# Reads  data/raw/pool_u23_defenders.csv   (made by scraping/04_build_pool.py)
# Writes figures/percentiles.png           his percentile per metric, in-pool
#        figures/distributions.png         pool distributions with him marked
#
# Run:  Rscript R/comparisons.R
#
# Pool logic: prefer players tagged is_cb == "True"; if the tagging came back
# too thin (Sofascore's characteristics endpoint is best-effort), fall back to
# all U23 defenders and say so on the chart subtitle.

required <- c("readr", "dplyr", "tidyr", "ggplot2", "scales")
to_install <- setdiff(required, rownames(installed.packages()))
if (length(to_install) > 0) install.packages(to_install)
library(dplyr)
library(tidyr)
library(ggplot2)

PLAYER_ID <- 1634980
POOL_CSV <- "data/raw/pool_u23_defenders.csv"
MIN_CB_POOL <- 15  # fewer tagged CBs than this -> fall back to all defenders

# ---- design tokens (light surface; single accent validated 3:1+) ------------
COL_SURFACE <- "#fcfcfb"
COL_TEXT    <- "#0b0b0b"
COL_TEXT_2  <- "#52514e"
COL_GRID    <- "#e8e7e3"
COL_ACCENT  <- "#2a78d6"  # Ahanor
COL_POOL    <- "#8f8d84"  # neutral context marks (the pool)

# Metrics to compare: column name -> readable label. Only columns actually
# present in the CSV are used, so a Sofascore field going missing shrinks the
# chart instead of breaking it. "lower is better" metrics get inverted so
# every percentile reads "higher = better".
METRICS <- c(
  rating                      = "Sofascore rating",
  tackles_per90               = "Tackles /90",
  interceptions_per90         = "Interceptions /90",
  clearances_per90            = "Clearances /90",
  ballRecovery_per90          = "Ball recoveries /90",
  blockedShots_per90          = "Blocked shots /90",
  aerialDuelsWon_per90        = "Aerial duels won /90",
  aerialDuelsWonPercentage    = "Aerial duel win %",
  totalDuelsWonPercentage     = "Duel win %",
  accuratePasses_per90        = "Accurate passes /90",
  accuratePassesPercentage    = "Pass accuracy %",
  accurateLongBalls_per90     = "Accurate long balls /90",
  possessionLost_per90        = "Possession lost /90"
)
LOWER_IS_BETTER <- c("possessionLost_per90")

theme_pitchside <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.background = element_rect(fill = COL_SURFACE, colour = NA),
      panel.background = element_rect(fill = COL_SURFACE, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = COL_GRID, linewidth = 0.4),
      text = element_text(colour = COL_TEXT),
      axis.text = element_text(colour = COL_TEXT_2),
      plot.title = element_text(face = "bold", size = 15),
      plot.subtitle = element_text(colour = COL_TEXT_2, size = 10),
      plot.caption = element_text(colour = COL_TEXT_2, size = 8),
      strip.text = element_text(colour = COL_TEXT_2, size = 9),
      legend.position = "top",
      legend.title = element_blank()
    )
}

# ---- load + choose the pool -------------------------------------------------
raw <- readr::read_csv(POOL_CSV, show_col_types = FALSE)
stopifnot(nrow(raw) > 0)

# The CSV stores is_cb as "True"/"False"/"" and readr may parse it as logical
# or character depending on the mix - normalize to logical either way.
raw <- raw |> mutate(is_cb = toupper(as.character(is_cb)) %in% "TRUE")

cbs <- raw |> filter(is_cb | player_id == PLAYER_ID)
if (sum(cbs$is_cb, na.rm = TRUE) >= MIN_CB_POOL) {
  pool <- cbs
  pool_label <- "U23 centre-backs, Big-5 leagues"
} else {
  message("CB tagging too thin (", sum(raw$is_cb, na.rm = TRUE),
          " tagged) - falling back to all U23 defenders")
  pool <- raw
  pool_label <- "U23 defenders, Big-5 leagues"
}

player <- pool |> filter(player_id == PLAYER_ID)
if (nrow(player) == 0) {
  stop("Ahanor (", PLAYER_ID, ") is not in ", POOL_CSV,
       " - check 04_build_pool.py output for the note about his row")
}

metrics <- METRICS[names(METRICS) %in% names(pool)]
# bar-chart labels flag the metrics whose percentile is inverted
metrics_bar <- metrics
inverted <- names(metrics_bar) %in% LOWER_IS_BETTER
metrics_bar[inverted] <- paste0(metrics_bar[inverted], " (inverted)")

season_label <- "Serie A + Big-5 peers, 2025-26"
caption_pct <- paste0("Data: Sofascore | pool: ", pool_label,
                      ", min. 600 league minutes | percentiles: higher = better")
caption_raw <- paste0("Data: Sofascore | raw per-90 / % values | pool: ",
                      pool_label, ", min. 600 league minutes")

long <- pool |>
  select(player_id, player_name, league, all_of(names(metrics))) |>
  pivot_longer(all_of(names(metrics)), names_to = "metric", values_to = "value") |>
  mutate(
    value = suppressWarnings(as.numeric(value)),
    # bars list best-first top-to-bottom (reversed); facets keep METRICS order
    label_bar = factor(metrics_bar[metric], levels = rev(unname(metrics_bar))),
    label = factor(metrics[metric], levels = unname(metrics))
  ) |>
  filter(!is.na(value))

# ---- chart 1: percentile bars ----------------------------------------------
percentiles <- long |>
  group_by(metric, label_bar) |>
  summarise(
    pct = 100 * mean(value <= value[player_id == PLAYER_ID][1], na.rm = TRUE),
    n = n(),
    .groups = "drop"
  ) |>
  filter(!is.na(pct)) |>
  mutate(pct = ifelse(metric %in% LOWER_IS_BETTER, 100 - pct, pct))

p1 <- ggplot(percentiles, aes(x = pct, y = label_bar)) +
  geom_col(fill = COL_ACCENT, width = 0.55) +
  geom_text(aes(label = round(pct)), hjust = -0.4, size = 3.2, colour = COL_TEXT) +
  scale_x_continuous(limits = c(0, 108), breaks = c(0, 25, 50, 75, 100),
                     expand = expansion(mult = c(0, 0))) +
  labs(
    title = "Honest Ahanor - percentile vs age-group peers",
    subtitle = paste0(pool_label, " (n = ", max(percentiles$n), ") | ", season_label),
    x = "percentile", y = NULL, caption = caption_pct
  ) +
  theme_pitchside() +
  theme(panel.grid.major.y = element_blank())

dir.create("figures", showWarnings = FALSE)
ggsave("figures/percentiles.png", p1, width = 8, height = 6, dpi = 150,
       bg = COL_SURFACE)
message("saved figures/percentiles.png")

# ---- chart 2: pool distributions with Ahanor marked -------------------------
long <- long |>
  mutate(who = ifelse(player_id == PLAYER_ID, "Honest Ahanor", pool_label))

p2 <- ggplot() +
  geom_jitter(
    data = filter(long, who != "Honest Ahanor"),
    aes(x = value, y = 0, colour = who),
    height = 0.32, size = 1.6, alpha = 0.55, na.rm = TRUE
  ) +
  geom_point(
    data = filter(long, who == "Honest Ahanor"),
    aes(x = value, y = 0, colour = who),
    size = 3.4, na.rm = TRUE
  ) +
  scale_colour_manual(values = setNames(
    c(COL_ACCENT, COL_POOL), c("Honest Ahanor", pool_label)
  )) +
  facet_wrap(~label, scales = "free_x", ncol = 3) +
  guides(colour = guide_legend(override.aes = list(size = 3, alpha = 1))) +
  labs(
    title = "Where Ahanor sits in each distribution",
    subtitle = paste0(pool_label, " | ", season_label),
    x = NULL, y = NULL, caption = caption_raw
  ) +
  theme_pitchside() +
  theme(
    axis.text.y = element_blank(),
    panel.grid.major.y = element_blank()
  )

ggsave("figures/distributions.png", p2, width = 10, height = 8, dpi = 150,
       bg = COL_SURFACE)
message("saved figures/distributions.png")
