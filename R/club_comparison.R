# club_comparison.R -----------------------------------------------------------
# The subject against the comparison club's same-role room - the "gap he
# fills" chart. Each metric is a row on a common percentile scale; the club's
# players are dots with a band spanning their range, the subject is the
# accent dot.
# Rows where his dot sits beyond the band are the gap.
#
# Percentiles are computed against ALL Big-5 players of the subject's coarse
# position (any age, 600+ league minutes, current season) so his U23 status
# doesn't distort the scale - the club's players are mostly older.
#
# Reads  data/raw/pool_all.csv    (04_build_pool.py)
#        data/raw/club_role.csv   (05_scrape_club_role.py)
# Writes figures/club_comparison.png
#
# Run:  Rscript R/club_comparison.R

source("R/viz_common.R")
require_subject()

# ---- titles: edit freely, nothing else depends on the wording ---------------
TITLE_CLUB <- "Measured for the Chelsea Flank"

pool <- readr::read_csv("data/raw/pool_all.csv", show_col_types = FALSE) |>
  filter(season == CURRENT_SEASON) |>
  # one row per player: a mid-season mover keeps his bigger league stint
  mutate(.min = suppressWarnings(as.numeric(minutesPlayed))) |>
  group_by(player_id) |>
  slice_max(.min, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(-.min)
club <- readr::read_csv("data/raw/club_role.csv", show_col_types = FALSE) |>
  mutate(is_role = toupper(as.character(is_role)) %in% "TRUE")

club_name <- club$team_name[1]
cbs <- club |> filter(is_role, player_id != PLAYER_ID)
role_text <- ROLE_LABEL
if (nrow(cbs) < 2) {
  message("fewer than 2 tagged ", ROLE_LABEL, " - using all ", club_name,
          " ", POSITION_LABEL)
  cbs <- club |> filter(player_id != PLAYER_ID)
  role_text <- POSITION_LABEL
}

# stats come from the all-ages pool; club players without a pool row
# (fewer than 600 league minutes) can't be compared fairly - list and drop
cbs_in_pool <- semi_join(pool, cbs, by = "player_id")
missing <- setdiff(cbs$player_name, cbs_in_pool$player_name)
if (length(missing) > 0) {
  message("not in the minutes-filtered pool (dropped): ",
          paste(missing, collapse = ", "))
}
if (nrow(cbs_in_pool) == 0) stop("no ", club_name, " ", role_text, " have pool rows")

subject <- pool |> filter(player_id == PLAYER_ID)
if (nrow(subject) == 0) stop(PLAYER_NAME, " missing from pool_all.csv")

# this chart sticks to concrete on-pitch metrics - the Sofascore rating is
# a black-box aggregate, so it is excluded here
metrics <- METRICS[names(METRICS) %in% names(pool) & names(METRICS) != "rating"]

# percentile of each target within the full pool, metric by metric
targets <- bind_rows(
  cbs_in_pool |> mutate(role = paste0(club_name, " ", role_text)),
  subject |> mutate(role = PLAYER_NAME)
)
pct_rows <- lapply(names(metrics), function(m) {
  pool_vals <- suppressWarnings(as.numeric(pool[[m]]))
  target_vals <- suppressWarnings(as.numeric(targets[[m]]))
  pct <- 100 * vapply(target_vals,
                      function(v) mean(pool_vals <= v, na.rm = TRUE),
                      numeric(1))
  if (m %in% LOWER_IS_BETTER) pct <- 100 - pct
  tibble::tibble(
    metric = m, player_name = targets$player_name, role = targets$role,
    pct = pct
  )
})
plot_df <- bind_rows(pct_rows) |>
  filter(!is.na(pct)) |>
  mutate(
    label = factor(metrics[metric], levels = rev(unname(metrics))),
    group = factor(METRIC_GROUPS[metric], levels = GROUP_ORDER)
  )

club_role <- paste0(club_name, " ", role_text)
band <- plot_df |>
  filter(role == club_role) |>
  group_by(label, group) |>
  summarise(lo = min(pct), hi = max(pct), .groups = "drop")

caption <- chart_footer(paste0(
  "Percentiles vs all Big-5 ", POSITION_LABEL, " (any age), min. 600 league minutes, ",
  CURRENT_SEASON, ". Higher = better"
))
subtitle <- paste0(
  club_name, " ", role_text, ": ",
  paste(sort(unique(cbs_in_pool$player_name)), collapse = ", ")
)

# dark rendition: the club's players wear blue (Chelsea's own colour), the
# subject the orange counter-accent - a validated pair on the dark surface
p <- ggplot() +
  geom_vline(xintercept = 50, colour = DK_GRID, linewidth = 0.6) +
  geom_segment(
    data = band, aes(x = lo, xend = hi, y = label, yend = label),
    colour = DK_ACCENT, alpha = 0.28, linewidth = 3.5, lineend = "round"
  ) +
  geom_point(
    data = filter(plot_df, role == club_role),
    aes(x = pct, y = label, fill = role),
    size = 2.6, shape = 21, colour = DK_INK, stroke = 0.5
  ) +
  geom_point(
    data = filter(plot_df, role == PLAYER_NAME),
    aes(x = pct, y = label, fill = role),
    size = 3.8, shape = 21, colour = DK_INK, stroke = 0.7
  ) +
  scale_fill_manual(values = setNames(
    c(DK_ACCENT2, DK_ACCENT), c(PLAYER_NAME, club_role)
  )) +
  scale_x_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100)) +
  facet_grid(rows = vars(group), scales = "free_y", space = "free_y",
             switch = "y") +
  guides(fill = guide_legend(override.aes = list(size = 3))) +
  labs(
    title = TITLE_CLUB, subtitle = subtitle,
    x = "Percentile", y = NULL, caption = caption
  ) +
  theme_pitchside_dark() +
  theme(
    panel.grid.major.y = element_blank(),
    strip.placement = "outside",
    strip.text.y.left = element_text(angle = 0, hjust = 1, vjust = 1),
    panel.spacing.y = unit(14, "pt")
  )

save_fig("figures/club_comparison.png", p, width = 9, height = 8,
         bg = DK_SURFACE)