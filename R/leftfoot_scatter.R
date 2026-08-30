# leftfoot_scatter.R ----------------------------------------------------------
# Interceptions/90 vs tackles/90 for LEFT-FOOTED defenders of ANY age,
# Big-5 leagues, 25/26. Ahanor (left-footed himself) is the orange
# highlight; left-footed defenders are scarce, so this is the market he
# actually competes in - veterans included.
#
# Reads  data/raw/pool_defenders_all.csv   (04_build_pool.py, all-ages pool)
# Writes figures/leftfooted_ball_winners.png
#
# Run:  Rscript R/leftfoot_scatter.R

# ── setup ────────────────────────────────────────────────────────────────────
# viz_common.R brings packages, fonts, the dark theme, shared colour tokens
# (DK_*), PLAYER_ID and CURRENT_SEASON.
source("R/viz_common.R")

# ── knobs: edit freely ───────────────────────────────────────────────────────
TITLE_LEFTIES <- "The Left-Footed Market"  # chart title
LEAGUE_FILTER  <- "premier-league"  # league slug from BIG5_LEAGUES; "" = all
MAX_ALL_LABELS <- 18   # label every player when the pool is this small or
                       # smaller; above it, only the best (plus Ahanor)
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
# pool_defenders_all.csv is the age-unfiltered pool (same 600-minute floor).
# Note: it carries no CB tag (only the U23 pool was position-enriched), so
# the comparison group is all left-footed defenders - and says so.
pool <- readr::read_csv("data/raw/pool_defenders_all.csv",
                        show_col_types = FALSE) |>
  filter(season == CURRENT_SEASON)

sc <- pool |>
  mutate(
    # numeric coercion: CSV round-trips can leave these as text
    t90  = suppressWarnings(as.numeric(tackles_per90)),
    i90  = suppressWarnings(as.numeric(interceptions_per90)),
    lefty = grepl("left", preferred_foot, ignore.case = TRUE)
  ) |>
  # the filter: left-footed, in the chosen league, with both metrics
  # present. Ahanor always survives - he is the subject of the chart, shown
  # for reference even though he plays outside the filtered league.
  filter(
    (lefty & (LEAGUE_FILTER == "" | league == LEAGUE_FILTER)) |
      player_id == PLAYER_ID,
    !is.na(t90), !is.na(i90)
  )

pool_label <- if (LEAGUE_FILTER == "premier-league") {
  "Left-footed Premier League defenders"
} else if (LEAGUE_FILTER == "") {
  "Left-footed defenders, Big-5 leagues"
} else {
  paste0("Left-footed defenders, ", LEAGUE_FILTER)
}
message(nrow(sc), " players in the left-footed pool")

# ── who gets a name label ────────────────────────────────────────────────────
# small pool: everyone. big pool: the N best by combined z-score, plus Ahanor.
if (nrow(sc) <= MAX_ALL_LABELS) {
  labeled <- sc
} else {
  others <- sc |> filter(player_id != PLAYER_ID)
  top_ids <- others$player_id[
    order(-(as.numeric(scale(others$t90)) + as.numeric(scale(others$i90))))
  ][1:N_TOP_LABELS]
  labeled <- sc |> filter(player_id %in% c(top_ids, PLAYER_ID))
}
message(nrow(labeled), " players named")

# split into the two visual roles: the highlight and the context
sc <- sc |>
  mutate(who = ifelse(player_id == PLAYER_ID, "Honest Ahanor", pool_label))

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
  geom_point(data = filter(sc, who != "Honest Ahanor"),
             aes(fill = who),
             size = 2.6, shape = 21, colour = DK_INK, stroke = 0.5) +
  # Ahanor: bigger, orange, same inked outline
  geom_point(data = filter(sc, who == "Honest Ahanor"),
             aes(fill = who),
             size = 4, shape = 21, colour = DK_INK, stroke = 0.7) +
  # name labels, collision-avoided; Ahanor included via `labeled`
  ggrepel::geom_text_repel(
    data = labeled, aes(label = player_name),
    size = 3, colour = DK_TEXT, family = FONT, seed = 7,
    segment.colour = DK_GRID, min.segment.length = 0.2, box.padding = 0.35
  ) +
  # fixed colour mapping: highlight orange, pool gray
  scale_fill_manual(values = setNames(
    c(DK_ACCENT2, DK_POOL), c("Honest Ahanor", pool_label)
  )) +
  guides(fill = guide_legend(override.aes = list(size = 3))) +
  # titles and framing text
  labs(
    title = TITLE_LEFTIES,
    subtitle = paste0("Tackles and interceptions per 90 - ", pool_label, ", ",
                      CURRENT_SEASON, "\nAhanor (Serie A) shown for ",
                      "reference. Dashed lines mark pool medians"),
    x = "Tackles per 90", y = "Interceptions per 90",
    caption = caption
  ) +
  theme_matte()

# ── export: 300 dpi on the matte surface ─────────────────────────────────────
save_fig("figures/leftfooted_ball_winners.png", p, width = 9, height = 7,
         bg = MT_SURFACE)
