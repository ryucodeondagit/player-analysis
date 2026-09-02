# leftfoot_scatter.R ----------------------------------------------------------
# Interceptions/90 vs tackles/90 for LEFT-FOOTED players of the subject's
# position, ANY age, Big-5 leagues, 25/26. The subject (left-footed himself)
# is the orange highlight; left-footed defenders are scarce, so this is the
# market he actually competes in - veterans included.
#
# Reads  data/raw/pool_all.csv   (04_build_pool.py, all-ages pool)
# Writes figures/leftfooted_ball_winners.png
#
# Run:  Rscript R/leftfoot_scatter.R

# ── setup ────────────────────────────────────────────────────────────────────
# viz_common.R brings packages, fonts, the dark theme, shared colour tokens
# (DK_*), the subject and CURRENT_SEASON.
source("R/viz_common.R")
require_subject()

# ── knobs: edit freely ───────────────────────────────────────────────────────
TITLE_LEFTIES <- "The Left-Footed Market"  # chart title
LEAGUE_FILTER  <- "premier-league"  # league slug from BIG5_LEAGUES; "" = all
MAX_ALL_LABELS <- 18   # label every player when the pool is this small or
                       # smaller; above it, only the best (plus the subject)
N_TOP_LABELS   <- 8    # how many get names when the pool is big

# ── surface: matte charcoal, a step lighter than the house dark ──────────────
# All mark colours were contrast-checked against this surface (>= 3:1).
MT_SURFACE <- "#252523"

theme_matte <- function() {
  # start from the shared dark theme, then repaint the two backgrounds
  theme_pitchside_dark() +
    theme(
      plot.background  = element_rect(fill = MT_SURFACE, colour = NA),
      panel.background = element_rect(fill = MT_SURFACE, colour = NA)
    )
}

# ── data: current season, left-footed, ALL ages ──────────────────────────────
# pool_all.csv is the age-unfiltered pool (same 600-minute floor). Note: it
# carries no role tag (only the U23 pool was position-enriched), so the
# comparison group is all left-footed players of the position - and says so.
pool <- readr::read_csv("data/raw/pool_all.csv",
                        show_col_types = FALSE) |>
  filter(season == CURRENT_SEASON) |>
  # one row per player: a mid-season mover keeps his bigger league stint
  mutate(.min = suppressWarnings(as.numeric(minutesPlayed))) |>
  group_by(player_id) |>
  slice_max(.min, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(-.min)

sc <- pool |>
  mutate(
    # numeric coercion: CSV round-trips can leave these as text
    t90  = suppressWarnings(as.numeric(tackles_per90)),
    i90  = suppressWarnings(as.numeric(interceptions_per90)),
    lefty = grepl("left", preferred_foot, ignore.case = TRUE)
  ) |>
  # the filter: left-footed, in the chosen league, with both metrics
  # present. The subject always survives - shown for reference even when
  # his 25/26 league is outside the filter.
  filter(
    (lefty & (LEAGUE_FILTER == "" | league == LEAGUE_FILTER)) |
      player_id == PLAYER_ID,
    !is.na(t90), !is.na(i90)
  )

pool_label <- if (LEAGUE_FILTER == "premier-league") {
  paste0("Left-footed Premier League ", POSITION_LABEL)
} else if (LEAGUE_FILTER == "") {
  paste0("Left-footed ", POSITION_LABEL, ", Big-5 leagues")
} else {
  paste0("Left-footed ", POSITION_LABEL, ", ", LEAGUE_FILTER)
}
subject_row <- sc |> filter(player_id == PLAYER_ID)
if (nrow(subject_row) == 0) stop(PLAYER_NAME, " has no 25/26 row in pool_all.csv")
subject_league <- c("premier-league" = "Premier League", laliga = "LaLiga",
                    "serie-a" = "Serie A", bundesliga = "Bundesliga",
                    "ligue-1" = "Ligue 1")[subject_row$league[1]]
message(nrow(sc), " players in the left-footed pool")

# ── visual roles ─────────────────────────────────────────────────────────────
# three groups: the subject (orange), everyone above BOTH pool medians - the
# complete ball-winners in the top-right quadrant - marked in blue, and
# the rest of the pool in gray
MARKED_LABEL <- "Above both medians"
med_t <- median(sc$t90)
med_i <- median(sc$i90)
sc <- sc |>
  mutate(who = case_when(
    player_id == PLAYER_ID ~ PLAYER_NAME,
    t90 > med_t & i90 > med_i ~ MARKED_LABEL,
    TRUE ~ pool_label
  ))
message(sum(sc$who == MARKED_LABEL), " players above both medians")

# ── who gets a name label ────────────────────────────────────────────────────
# everyone marked: the whole above-both-medians group and the subject; plus, in
# a big pool, the N best combined performers keep their names too
if (nrow(sc) <= MAX_ALL_LABELS) {
  labeled <- sc
} else {
  others <- sc |> filter(player_id != PLAYER_ID)
  top_ids <- others$player_id[
    order(-(as.numeric(scale(others$t90)) + as.numeric(scale(others$i90))))
  ][1:N_TOP_LABELS]
  labeled <- sc |>
    filter(player_id %in% c(top_ids, PLAYER_ID) | who == MARKED_LABEL)
}
message(nrow(labeled), " players named")

# ── chart ────────────────────────────────────────────────────────────────────
caption <- chart_footer(paste0("Pool: ", pool_label,
                               ", min. 600 league minutes"))

p <- ggplot(sc, aes(x = t90, y = i90)) +
  # quadrant guides: dashed pool medians split the plane into four stories
  geom_hline(yintercept = median(sc$i90), colour = DK_GRID,
             linetype = "dashed", linewidth = 0.4) +
  geom_vline(xintercept = median(sc$t90), colour = DK_GRID,
             linetype = "dashed", linewidth = 0.4) +
  # context players: neutral gray, inked outline (the house border style)
  geom_point(data = filter(sc, who == pool_label),
             aes(fill = who),
             size = 2.6, shape = 21, colour = DK_INK, stroke = 0.5) +
  # above-both-medians group: marked in blue, slightly larger than the pool
  geom_point(data = filter(sc, who == MARKED_LABEL),
             aes(fill = who),
             size = 3, shape = 21, colour = DK_INK, stroke = 0.6) +
  # the subject: biggest, orange, same inked outline
  geom_point(data = filter(sc, who == PLAYER_NAME),
             aes(fill = who),
             size = 4, shape = 21, colour = DK_INK, stroke = 0.7) +
  # name labels, collision-avoided; the subject included via `labeled`
  ggrepel::geom_text_repel(
    data = labeled, aes(label = player_name),
    size = 3, colour = DK_TEXT, family = FONT, seed = 7,
    segment.colour = DK_GRID, min.segment.length = 0.2, box.padding = 0.35
  ) +
  # fixed colour mapping: subject orange, marked group blue, pool gray
  scale_fill_manual(values = setNames(
    c(DK_ACCENT2, DK_ACCENT, DK_POOL),
    c(PLAYER_NAME, MARKED_LABEL, pool_label)
  )) +
  guides(fill = guide_legend(override.aes = list(size = 3))) +
  # titles and framing text
  labs(
    title = TITLE_LEFTIES,
    subtitle = paste0("Tackles and interceptions per 90 - ", pool_label, ", ",
                      CURRENT_SEASON, "\n", PLAYER_NAME, " (", subject_league,
                      ") shown for reference. Dashed lines mark pool medians"),
    x = "Tackles per 90", y = "Interceptions per 90",
    caption = caption
  ) +
  theme_matte()

# ── export: 300 dpi on the matte surface ─────────────────────────────────────
save_fig("figures/leftfooted_ball_winners.png", p, width = 9, height = 7,
         bg = MT_SURFACE)
