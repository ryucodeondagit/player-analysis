# midfield_creation_share.R ---------------------------------------------------
# "Who created for Chelsea's midfield?" - one 100% stacked bar per metric,
# split by player, for the last full season (MIDFIELD_SEASON, 25/26).
# The first row is minutes: it is the baseline. If the departed player's
# share of key passes / big chances / assists is far bigger than his share of
# minutes, the hole is not "one starter" - it is the creation itself.
#
# Reads  data/raw/chelsea_midfield_stats.csv   (06_scrape_chelsea_midfield.py)
#        data/raw/pool_pl_midfielders.csv      (07_build_midfield_pool.py;
#                                               only for the 25/26 club)
# Writes figures/midfield_creation_share.png
#
# Run:  Rscript R/midfield_creation_share.R

source("R/viz_common.R")

# ---- knobs: edit freely -----------------------------------------------------
TITLE_SHARE <- "Who Created for Chelsea's Midfield?"
SEASON      <- "25/26"
CLUB        <- "Chelsea"
N_NAMED     <- 4     # departed + 3 biggest remaining get a hue; rest = "Others"
MIN_LABEL   <- 6     # % share below which no number is printed in a segment

# metric column -> row label (rows appear top to bottom in this order)
SHARE_METRICS <- c(
  minutesPlayed     = "Minutes played",
  keyPasses         = "Key passes",
  bigChancesCreated = "Big chances created",
  expectedAssists   = "Expected assists (xA)",
  assists           = "Assists"
)

# ---- data -------------------------------------------------------------------
stats <- readr::read_csv("data/raw/chelsea_midfield_stats.csv",
                         show_col_types = FALSE)
pool <- readr::read_csv("data/raw/pool_pl_midfielders.csv",
                        show_col_types = FALSE) |>
  select(player_id, team_name)

# the club's own midfield that season: departed + stays, and the evidence
# season must be the club's league season (a new signing's row is another
# club's - it has no place in this chart)
mid <- stats |>
  filter(role %in% c("departed", "stays")) |>
  left_join(pool, by = "player_id") |>
  mutate(team_name = coalesce(team_name, CLUB))
dropped <- mid |> filter(!grepl(CLUB, team_name, ignore.case = TRUE))
if (nrow(dropped) > 0) {
  message("not at ", CLUB, " in ", SEASON, " (dropped): ",
          paste(dropped$player_name, collapse = ", "))
}
mid <- mid |> filter(grepl(CLUB, team_name, ignore.case = TRUE))
if (nrow(mid) < 2) stop("fewer than 2 ", CLUB, " midfielders in the stats file")

metrics <- SHARE_METRICS[names(SHARE_METRICS) %in% names(mid)]

long <- mid |>
  select(player_id, player_name, role, all_of(names(metrics))) |>
  pivot_longer(all_of(names(metrics)), names_to = "metric", values_to = "value") |>
  mutate(value = suppressWarnings(as.numeric(value))) |>
  filter(!is.na(value))

# ---- who gets a name: departed first, then the biggest by minutes ----------
minutes <- mid |>
  mutate(m = suppressWarnings(as.numeric(minutesPlayed))) |>
  arrange(role != "departed", desc(m))
named <- head(minutes$player_name, N_NAMED)
others_label <- "Others"
long <- long |>
  mutate(series = ifelse(player_name %in% named, player_name, others_label)) |>
  group_by(metric, series) |>
  summarise(value = sum(value), .groups = "drop") |>
  group_by(metric) |>
  mutate(share = 100 * value / sum(value)) |>
  ungroup()

departed_name <- minutes$player_name[minutes$role == "departed"][1]
series_levels <- c(named, others_label)
series_levels <- series_levels[series_levels %in% long$series]
# orange for the hole, then green / gold / blue for the remaining names,
# gray for the fold - a validated 5-slot order on the matte surface
series_cols <- setNames(
  c(DK_ACCENT2, "#199e70", "#c98500", DK_ACCENT, DK_POOL)[seq_along(series_levels)],
  series_levels
)
series_cols[others_label] <- DK_POOL

plot_df <- long |>
  mutate(
    series = factor(series, levels = series_levels),
    row = factor(metrics[metric], levels = rev(unname(metrics))),
    label = ifelse(share >= MIN_LABEL, paste0(round(share), "%"), "")
  )

# ---- headline: minutes share vs creation share of the departed player -----
share_of <- function(m) {
  v <- plot_df |> filter(metric == m, series == departed_name)
  if (nrow(v) == 0) NA_real_ else round(v$share)
}
creation_metric <- if ("keyPasses" %in% names(metrics)) "keyPasses" else names(metrics)[2]
subtitle <- if (!is.na(share_of("minutesPlayed")) && !is.na(share_of(creation_metric))) {
  paste0(departed_name, " played ", share_of("minutesPlayed"),
         "% of the midfield's minutes and produced ",
         share_of(creation_metric), "% of its ",
         tolower(metrics[creation_metric]), " - ", CLUB, ", ", SEASON)
} else {
  paste0(CLUB, " central midfielders, ", SEASON, " Premier League")
}

folded <- setdiff(mid$player_name, named)
caption <- chart_footer(paste0(
  "Share of the ", CLUB, " central-midfield total, ", SEASON, " Premier League",
  if (length(folded) > 0) paste0(". Others: ", paste(sort(folded), collapse = ", ")) else ""
))

# ---- chart ------------------------------------------------------------------
p <- ggplot(plot_df, aes(x = share, y = row, fill = series)) +
  # stacked left to right in series order; surface-coloured borders are the
  # 2px gap that keeps adjacent segments apart without a legend lookup
  geom_col(position = position_stack(reverse = TRUE), width = 0.62,
           colour = MT_SURFACE, linewidth = 0.9) +
  geom_text(aes(label = label),
            position = position_stack(reverse = TRUE, vjust = 0.5),
            colour = DK_TEXT, size = 3.1, fontface = "bold", family = FONT) +
  scale_fill_manual(values = series_cols, breaks = series_levels) +
  scale_x_continuous(limits = c(0, 100), expand = c(0, 0),
                     breaks = c(0, 25, 50, 75, 100),
                     labels = function(x) paste0(x, "%")) +
  labs(title = TITLE_SHARE, subtitle = subtitle, x = NULL, y = NULL,
       caption = caption) +
  theme_pitchside_dark() +
  theme(
    plot.background  = element_rect(fill = MT_SURFACE, colour = NA),
    panel.background = element_rect(fill = MT_SURFACE, colour = NA),
    panel.border = element_blank(),
    panel.grid.major.y = element_blank(),
    axis.text.y = element_text(size = 10.5, colour = DK_TEXT),
    legend.key.size = unit(10, "pt")
  )

save_fig("figures/midfield_creation_share.png", p, width = 10, height = 5.6,
         bg = MT_SURFACE)
