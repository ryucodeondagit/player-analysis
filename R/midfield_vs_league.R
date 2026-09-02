# midfield_vs_league.R --------------------------------------------------------
# Chelsea's 25/26 midfield unit against the other 19 Premier League midfield
# units, key stat by key stat. Each club's midfielders are pooled into one
# team rate (sum of the stat over the unit's minutes, per 90; percentages
# are minutes-weighted). Chelsea is the blue dot with its rank; a hollow
# orange dot re-computes Chelsea WITHOUT the departed player(s) from the
# roster file, so the same row shows where the unit sits and where it would
# have sat without him.
#
# Reads  data/raw/pool_pl_midfielders.csv   (07_build_midfield_pool.py)
# Writes figures/midfield_vs_league.png      dot strips, one per key stat
#        figures/midfield_rank_card.png      Chelsea's rank per stat, at a glance
#
# Run:  Rscript R/midfield_vs_league.R

source("R/viz_common.R")

# ---- knobs: edit freely -----------------------------------------------------
TITLE_STRIPS <- "Chelsea's Midfield Against the League"
TITLE_RANKS  <- "Where Chelsea's Midfield Ranks"
SEASON       <- "25/26"
CLUB         <- "Chelsea"
WITHOUT_DEPARTED <- TRUE   # add the "without the departed player" marker

# key stats: column -> label. Counts become team rates per 90 midfield
# minutes; columns ending in Percentage are minutes-weighted means.
KEY_STATS <- c(
  keyPasses                = "Key passes /90",
  bigChancesCreated        = "Big chances created /90",
  expectedAssists          = "Expected assists /90",
  assists                  = "Assists /90",
  successfulDribbles       = "Successful dribbles /90",
  accuratePassesPercentage = "Pass accuracy %",
  possessionLost           = "Possession lost /90",
  tackles                  = "Tackles /90",
  interceptions            = "Interceptions /90",
  ballRecovery             = "Ball recoveries /90",
  totalDuelsWonPercentage  = "Duel win %"
)
STAT_GROUPS <- c(
  keyPasses = "Creating", bigChancesCreated = "Creating",
  expectedAssists = "Creating", assists = "Creating",
  successfulDribbles = "On the ball", accuratePassesPercentage = "On the ball",
  possessionLost = "On the ball",
  tackles = "Defending", interceptions = "Defending",
  ballRecovery = "Defending", totalDuelsWonPercentage = "Defending"
)
GROUPS <- c("Creating", "On the ball", "Defending")
LOWER_BETTER <- c("possessionLost")

# ---- data -------------------------------------------------------------------
pool <- readr::read_csv("data/raw/pool_pl_midfielders.csv",
                        show_col_types = FALSE) |>
  mutate(
    role = coalesce(as.character(role), ""),
    minutes = suppressWarnings(as.numeric(minutesPlayed))
  ) |>
  filter(!is.na(minutes), minutes > 0, !is.na(team_name))

stats <- names(KEY_STATS)[names(KEY_STATS) %in% names(pool)]
if (length(stats) == 0) stop("none of KEY_STATS found in pool_pl_midfielders.csv")

# team rate for one stat over a set of player rows
team_rate <- function(df, stat) {
  v <- suppressWarnings(as.numeric(df[[stat]]))
  ok <- !is.na(v)
  if (!any(ok)) return(NA_real_)
  if (grepl("Percentage$", stat)) {
    sum(v[ok] * df$minutes[ok]) / sum(df$minutes[ok])       # minutes-weighted mean
  } else {
    sum(v[ok]) / sum(df$minutes[ok]) * 90                    # per 90 unit minutes
  }
}

aggregate_units <- function(df, unit_label) {
  df |>
    group_by(team_name) |>
    group_modify(function(g, key) {
      tibble::tibble(
        stat = stats,
        value = vapply(stats, function(s) team_rate(g, s), numeric(1)),
        n_players = nrow(g),
        unit_minutes = sum(g$minutes)
      )
    }) |>
    ungroup() |>
    mutate(unit = unit_label)
}

units <- aggregate_units(pool, "club")
is_club <- grepl(CLUB, units$team_name, ignore.case = TRUE)
if (!any(is_club)) stop(CLUB, " not found among team_name values")
n_clubs <- length(unique(units$team_name))
message(n_clubs, " clubs; ", CLUB, " midfield = ",
        units$n_players[is_club][1], " players, ",
        round(units$unit_minutes[is_club][1]), " minutes")

# rank within each stat (1 = best), direction-aware
units <- units |>
  group_by(stat) |>
  mutate(rank = ifelse(stat %in% LOWER_BETTER, rank(value), rank(-value)),
         median = median(value, na.rm = TRUE)) |>
  ungroup()

# the counterfactual unit: Chelsea's rows minus the departed player(s)
departed <- pool |> filter(grepl(CLUB, team_name, ignore.case = TRUE),
                           role == "departed")
without <- NULL
if (WITHOUT_DEPARTED && nrow(departed) > 0) {
  remaining <- pool |>
    filter(grepl(CLUB, team_name, ignore.case = TRUE), role != "departed")
  without <- aggregate_units(remaining, "without") |>
    mutate(team_name = paste0(CLUB, " without ",
                              paste(departed$player_name, collapse = " & ")))
  # where would that unit rank among the other 19 + itself?
  others <- units |> filter(!grepl(CLUB, team_name, ignore.case = TRUE))
  without <- without |>
    rowwise() |>
    mutate(rank = {
      o <- others$value[others$stat == stat]
      if (stat %in% LOWER_BETTER) sum(o < value) + 1 else sum(o > value) + 1
    }) |>
    ungroup()
  message("counterfactual unit: ", without$team_name[1], " (",
          without$n_players[1], " players)")
}

ordinal <- function(n) {
  suffix <- ifelse(n %% 100 %in% 11:13, "th",
                   c("th", "st", "nd", "rd", rep("th", 6))[n %% 10 + 1])
  paste0(n, suffix)
}

# ---- chart 1: one strip per key stat ----------------------------------------
plot_units <- units |>
  mutate(
    who = ifelse(grepl(CLUB, team_name, ignore.case = TRUE), CLUB, "Other PL clubs"),
    label = factor(KEY_STATS[stat], levels = unname(KEY_STATS[stats])),
    group = factor(STAT_GROUPS[stat], levels = GROUPS)
  )
club_pts <- plot_units |> filter(who == CLUB) |>
  mutate(text = paste0(CLUB, " · ", ordinal(rank), " of ", n_clubs))
best_pts <- plot_units |> filter(rank == 1, who != CLUB)
without_lab <- if (!is.null(without)) "Without the departed player" else NULL
without_pts <- if (!is.null(without)) {
  without |> mutate(
    label = factor(KEY_STATS[stat], levels = unname(KEY_STATS[stats])),
    group = factor(STAT_GROUPS[stat], levels = GROUPS),
    who = without_lab,
    text = paste0("without · ", ordinal(rank))
  )
} else NULL

legend_levels <- c(CLUB, without_lab, "Other PL clubs")
# the counterfactual is a hollow marker: surface fill, orange stroke
legend_cols <- setNames(c(DK_ACCENT, if (!is.null(without)) MT_SURFACE, DK_POOL),
                        legend_levels)
legend_strokes <- setNames(c(DK_INK, if (!is.null(without)) DK_ACCENT2, DK_INK),
                           legend_levels)

caption <- chart_footer(paste0(
  "Each dot is one club's midfield unit: Sofascore position M, ", SEASON,
  " Premier League, 600+ league minutes per player. Rates are per 90 unit ",
  "minutes; percentages minutes-weighted. Dashed line = league median"
))

p1 <- ggplot() +
  geom_vline(data = distinct(plot_units, label, group, median),
             aes(xintercept = median),
             colour = DK_GRID, linetype = "dashed", linewidth = 0.45) +
  geom_point(data = filter(plot_units, who != CLUB),
             aes(x = value, y = 0, fill = who),
             shape = 21, size = 3, colour = DK_INK, stroke = 0.5, alpha = 0.85) +
  ggrepel::geom_text_repel(
    data = best_pts, aes(x = value, y = 0, label = team_name),
    size = 2.7, colour = DK_TEXT_2, family = FONT, nudge_y = 0.55,
    direction = "x", segment.colour = DK_GRID, seed = 3
  ) +
  {
    if (!is.null(without_pts))
      list(
        geom_point(data = without_pts, aes(x = value, y = 0, fill = who),
                   shape = 21, size = 4.4, colour = DK_ACCENT2, stroke = 1.1),
        ggrepel::geom_text_repel(
          data = without_pts, aes(x = value, y = 0, label = text),
          size = 2.9, colour = DK_ACCENT2, family = FONT, nudge_y = -0.6,
          direction = "x", segment.colour = DK_GRID, seed = 5
        )
      )
  } +
  geom_point(data = club_pts, aes(x = value, y = 0, fill = who),
             shape = 21, size = 5, colour = DK_INK, stroke = 0.8) +
  ggrepel::geom_text_repel(
    data = club_pts, aes(x = value, y = 0, label = text),
    size = 3.1, colour = DK_TEXT, fontface = "bold", family = FONT,
    nudge_y = 0.6, direction = "x", segment.colour = DK_GRID, seed = 5
  ) +
  scale_fill_manual(values = legend_cols, breaks = legend_levels) +
  scale_y_continuous(limits = c(-1, 1), breaks = NULL) +
  facet_wrap(~label, scales = "free_x", ncol = 2, dir = "v") +
  guides(fill = guide_legend(override.aes = list(
    size = 3.5, alpha = 1, colour = legend_strokes[legend_levels], stroke = 1
  ))) +
  labs(
    title = TITLE_STRIPS,
    subtitle = paste0(CLUB, "'s midfield unit vs the other ", n_clubs - 1,
                      " Premier League midfields, ", SEASON,
                      ". Right-hand side is better, except possession lost"),
    x = NULL, y = NULL, caption = caption
  ) +
  theme_pitchside_dark() +
  theme(
    plot.background  = element_rect(fill = MT_SURFACE, colour = NA),
    panel.background = element_rect(fill = MT_SURFACE, colour = NA),
    panel.grid.major.y = element_blank(),
    panel.border = element_blank(),
    strip.text = element_text(size = 10, colour = DK_TEXT, hjust = 0),
    panel.spacing.y = unit(4, "pt"),
    panel.spacing.x = unit(22, "pt")
  )

n_rows <- ceiling(length(stats) / 2)
save_fig("figures/midfield_vs_league.png", p1, width = 12,
         height = 1.55 * n_rows + 2.6, bg = MT_SURFACE)

# ---- chart 2: the rank card --------------------------------------------------
# One row per stat, x = rank among the league's midfields (1 = best). Blue
# = Chelsea 25/26; hollow orange = the same unit without the departed
# player. The arrow between them is the drop.
rank_df <- club_pts |> select(label, group, rank) |> mutate(who = CLUB)
if (!is.null(without_pts)) {
  rank_df <- bind_rows(rank_df,
                       without_pts |> select(label, group, rank) |> mutate(who = without_lab))
}
rank_df <- rank_df |> mutate(label = factor(label, levels = rev(levels(label))))
seg <- rank_df |>
  group_by(label, group) |>
  summarise(from = rank[who == CLUB][1],
            to = if (any(who != CLUB)) rank[who != CLUB][1] else NA_real_,
            .groups = "drop") |>
  filter(!is.na(to), to != from)

p2 <- ggplot(rank_df, aes(x = rank, y = label)) +
  geom_vline(xintercept = (n_clubs + 1) / 2, colour = DK_GRID,
             linetype = "dashed", linewidth = 0.5) +
  geom_segment(data = seg,
               aes(x = from, xend = to - sign(to - from) * 0.45,
                   y = label, yend = label),
               colour = DK_ACCENT2, linewidth = 0.9,
               arrow = arrow(length = unit(6, "pt"), type = "closed")) +
  geom_point(data = filter(rank_df, who != CLUB), aes(fill = who),
             shape = 21, size = 4.2, colour = DK_ACCENT2, stroke = 1.1) +
  geom_point(data = filter(rank_df, who == CLUB), aes(fill = who),
             shape = 21, size = 5, colour = DK_INK, stroke = 0.8) +
  geom_text(data = filter(rank_df, who == CLUB),
            aes(label = ordinal(rank)), nudge_y = 0.38, size = 3,
            colour = DK_TEXT, family = FONT, fontface = "bold") +
  geom_text(data = filter(rank_df, who != CLUB),
            aes(label = ordinal(rank)), nudge_y = -0.38, size = 3,
            colour = DK_ACCENT2, family = FONT) +
  scale_fill_manual(values = legend_cols,
                    breaks = legend_levels[legend_levels != "Other PL clubs"]) +
  guides(fill = guide_legend(override.aes = list(
    size = 3.5, colour = legend_strokes[legend_levels[legend_levels != "Other PL clubs"]],
    stroke = 1
  ))) +
  scale_x_continuous(breaks = c(1, 5, 10, 15, n_clubs), limits = c(0.5, n_clubs + 0.5),
                     labels = function(x) ifelse(x == 1, "1st (best)",
                                                 ifelse(x == n_clubs, paste0(n_clubs, "th"), x))) +
  facet_grid(rows = vars(group), scales = "free_y", space = "free_y", switch = "y") +
  labs(
    title = TITLE_RANKS,
    subtitle = paste0("Rank of ", CLUB, "'s midfield unit among the ", n_clubs,
                      " Premier League midfields, ", SEASON,
                      if (!is.null(without)) ". Arrows: the same unit without the departed player" else ""),
    x = "Rank among Premier League midfields", y = NULL,
    caption = chart_footer(paste0(
      "1 = best. Units: Sofascore position M, 600+ league minutes per player, ",
      SEASON, " Premier League"))
  ) +
  theme_pitchside_dark() +
  theme(
    plot.background  = element_rect(fill = MT_SURFACE, colour = NA),
    panel.background = element_rect(fill = MT_SURFACE, colour = NA),
    panel.grid.major.y = element_blank(),
    strip.placement = "outside",
    strip.text.y.left = element_text(angle = 0, hjust = 1, vjust = 1),
    panel.spacing.y = unit(14, "pt"),
    axis.text.y = element_text(size = 10, colour = DK_TEXT)
  )

save_fig("figures/midfield_rank_card.png", p2, width = 10,
         height = 0.5 * length(stats) + 2.8, bg = MT_SURFACE)
