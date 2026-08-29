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

source("R/viz_common.R")  # packages, tokens, theme, PLAYER_ID, CURRENT_SEASON

# ---- titles: edit freely, nothing else depends on the wording ---------------
TITLE_PERCENTILES   <- "Ahanor Against His Generation"
TITLE_DISTRIBUTIONS <- "The U23 Field, Metric by Metric"
TITLE_SCATTER       <- "The Ball-Winning Plane"

POOL_CSV <- "data/raw/pool_u23_defenders.csv"
MIN_CB_POOL <- 15  # fewer tagged CBs than this -> fall back to all defenders

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

# metric families - the percentile chart groups its bars by these
METRIC_GROUPS <- c(
  rating = "Overall",
  tackles_per90 = "Defending", interceptions_per90 = "Defending",
  clearances_per90 = "Defending", ballRecovery_per90 = "Defending",
  blockedShots_per90 = "Defending",
  aerialDuelsWon_per90 = "Duels", aerialDuelsWonPercentage = "Duels",
  totalDuelsWonPercentage = "Duels",
  accuratePasses_per90 = "On the ball", accuratePassesPercentage = "On the ball",
  accurateLongBalls_per90 = "On the ball", possessionLost_per90 = "On the ball"
)
GROUP_ORDER <- c("Overall", "Defending", "Duels", "On the ball")

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

caption_pct <- chart_footer(paste0(
  "Pool: ", pool_label, ", min. 600 league minutes, U23 at each season's end. ",
  "Higher percentile = better"
))
caption_raw <- chart_footer(paste0(
  "Pool: ", pool_label, ", min. 600 league minutes"
))

long <- pool |>
  select(player_id, player_name, league, season, all_of(names(metrics))) |>
  pivot_longer(all_of(names(metrics)), names_to = "metric", values_to = "value") |>
  mutate(
    value = suppressWarnings(as.numeric(value)),
    # bars list best-first top-to-bottom (reversed); facets keep METRICS order
    label_bar = factor(metrics_bar[metric], levels = rev(unname(metrics_bar))),
    label = factor(metrics[metric], levels = unname(metrics)),
    group = factor(METRIC_GROUPS[metric], levels = GROUP_ORDER)
  ) |>
  filter(!is.na(value))

# ---- chart 1: percentile bars, one bar per season ---------------------------
# Percentiles are computed WITHIN each season's own pool, so 24/25 and 25/26
# are each a fair like-for-like comparison.
percentiles <- long |>
  group_by(season, metric, label_bar, group) |>
  summarise(
    pct = 100 * mean(value <= value[player_id == PLAYER_ID][1], na.rm = TRUE),
    n = n(),
    .groups = "drop"
  ) |>
  filter(!is.na(pct)) |>
  mutate(pct = ifelse(metric %in% LOWER_IS_BETTER, 100 - pct, pct))

pool_sizes <- percentiles |>
  group_by(season) |>
  summarise(n = max(n), .groups = "drop")
subtitle_pct <- paste0(
  pool_label, " | pool size: ",
  paste0(pool_sizes$n, " (", pool_sizes$season, ")", collapse = ", ")
)

# current season carries the accent; the previous season is gray context
season_cols <- setNames(c(COL_POOL, COL_ACCENT),
                        c(setdiff(unique(percentiles$season), CURRENT_SEASON)[1],
                          CURRENT_SEASON))

p1 <- ggplot(percentiles,
             aes(x = pct, y = label_bar, fill = season, group = season)) +
  geom_vline(xintercept = 50, colour = COL_GRID, linewidth = 0.6) +
  geom_col(width = 0.65, position = position_dodge(width = 0.72)) +
  geom_text(aes(label = round(pct)),
            position = position_dodge(width = 0.72),
            hjust = -0.4, size = 2.9, colour = COL_TEXT, family = FONT) +
  scale_fill_manual(values = season_cols, na.value = COL_GRID) +
  scale_x_continuous(limits = c(0, 108), breaks = c(0, 25, 50, 75, 100),
                     expand = expansion(mult = c(0, 0))) +
  facet_grid(rows = vars(group), scales = "free_y", space = "free_y",
             switch = "y") +
  labs(
    title = TITLE_PERCENTILES,
    subtitle = subtitle_pct,
    x = "Percentile", y = NULL, caption = caption_pct
  ) +
  theme_pitchside() +
  theme(
    panel.grid.major.y = element_blank(),
    strip.placement = "outside",
    strip.text.y.left = element_text(angle = 0, hjust = 1, vjust = 1),
    panel.spacing.y = unit(14, "pt")
  )

save_fig("figures/percentiles.png", p1, width = 8.5, height = 9.5)

# ---- chart 2: pool distributions with Ahanor marked (current season) --------
long <- long |>
  filter(season == CURRENT_SEASON) |>
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
    title = TITLE_DISTRIBUTIONS,
    subtitle = paste0(pool_label, ", ", CURRENT_SEASON, " season - raw values"),
    x = NULL, y = NULL, caption = caption_raw
  ) +
  theme_pitchside() +
  theme(
    axis.text.y = element_blank(),
    panel.grid.major.y = element_blank()
  )

save_fig("figures/distributions.png", p2, width = 10, height = 8)

# ---- chart 3: tackles/90 vs interceptions/90, 25/26 -------------------------
# The ball-winning plane. Top-right = high in both. The 6 best combined
# performers (z-scored sum of the two rates) are named; Ahanor is always
# named and keeps his own accent.
sc <- pool |>
  filter(season == CURRENT_SEASON) |>
  mutate(
    t90 = suppressWarnings(as.numeric(tackles_per90)),
    i90 = suppressWarnings(as.numeric(interceptions_per90))
  ) |>
  filter(!is.na(t90), !is.na(i90))

others <- sc |> filter(player_id != PLAYER_ID)
top_ids <- others$player_id[
  order(-(as.numeric(scale(others$t90)) + as.numeric(scale(others$i90))))
][1:6]

sc <- sc |>
  mutate(grp = case_when(
    player_id == PLAYER_ID ~ "Honest Ahanor",
    player_id %in% top_ids ~ "Top ball-winners",
    TRUE ~ pool_label
  ))
labeled <- sc |> filter(grp != pool_label)

# quadrant notes sit in the empty corners; small, italic, out of the way
corner <- function(x, y, label, hjust, vjust) {
  annotate("text", x = x, y = y, label = label, hjust = hjust, vjust = vjust,
           size = 2.8, colour = COL_TEXT_2, fontface = "italic", family = FONT)
}
xr <- range(sc$t90); yr <- range(sc$i90)

p3 <- ggplot(sc, aes(x = t90, y = i90, colour = grp)) +
  geom_hline(yintercept = median(sc$i90), colour = COL_GRID,
             linetype = "dashed", linewidth = 0.4) +
  geom_vline(xintercept = median(sc$t90), colour = COL_GRID,
             linetype = "dashed", linewidth = 0.4) +
  corner(xr[2], yr[2], "Wins it both ways", 1, 0.5) +
  corner(xr[1], yr[2], "Reads the game", 0, 0.5) +
  corner(xr[2], yr[1], "Front-foot tackler", 1, 0.5) +
  geom_point(data = filter(sc, grp == pool_label), size = 1.8, alpha = 0.55) +
  geom_point(data = filter(sc, grp == "Top ball-winners"), size = 2.6) +
  geom_point(data = filter(sc, grp == "Honest Ahanor"), size = 3.4) +
  ggrepel::geom_text_repel(
    data = labeled, aes(label = player_name),
    size = 3, colour = COL_TEXT, seed = 7, family = FONT,
    segment.colour = COL_GRID, min.segment.length = 0.2,
    box.padding = 0.35, show.legend = FALSE
  ) +
  scale_colour_manual(values = setNames(
    c(COL_ACCENT, COL_ACCENT2, COL_POOL),
    c("Honest Ahanor", "Top ball-winners", pool_label)
  )) +
  labs(
    title = TITLE_SCATTER,
    subtitle = paste0("Tackles and interceptions per 90 - ", pool_label, ", ",
                      CURRENT_SEASON, " season. Dashed lines mark pool medians"),
    x = "Tackles per 90", y = "Interceptions per 90",
    caption = caption_raw
  ) +
  theme_pitchside()

save_fig("figures/tackles_vs_interceptions.png", p3, width = 9, height = 7)
