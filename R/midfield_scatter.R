# midfield_scatter.R ----------------------------------------------------------
# The two-axis midfield map: every Premier League midfielder (25/26, 600+
# minutes) by defensive work (tackles + interceptions per 90) and creation
# (key passes per 90). Chelsea's roster is highlighted by role. The message
# is the shape: the remaining Chelsea dots cluster in the destroyer corner
# and the one dot in the creator corner is the departed one.
#
# Reads  data/raw/pool_pl_midfielders.csv   (07_build_midfield_pool.py)
# Writes figures/midfield_map.png
#
# Run:  Rscript R/midfield_scatter.R

source("R/viz_common.R")

# ---- knobs: edit freely -----------------------------------------------------
TITLE_MAP    <- "The Midfield Map Without Enzo"
SEASON       <- "25/26"
N_TOP_LABELS <- 8   # league's best creators named for context
CLUB         <- "Chelsea"

# ---- data -------------------------------------------------------------------
pool <- readr::read_csv("data/raw/pool_pl_midfielders.csv",
                        show_col_types = FALSE)

sc <- pool |>
  mutate(
    def90 = suppressWarnings(as.numeric(tackles_per90)) +
            suppressWarnings(as.numeric(interceptions_per90)),
    kp90  = suppressWarnings(as.numeric(keyPasses_per90)),
    role  = coalesce(as.character(role), "")
  ) |>
  filter(!is.na(def90), !is.na(kp90))
if (nrow(sc) < 10) stop("pool too small - check pool_pl_midfielders.csv")

POOL_LABEL <- "Premier League midfielders"
ROLE_LABELS <- c(
  "departed"    = "Departed",
  "stays"       = paste0(CLUB, " midfield, 26/27"),
  "new signing" = "New signing"
)
sc <- sc |>
  mutate(who = ifelse(role %in% names(ROLE_LABELS), ROLE_LABELS[role], POOL_LABEL))
who_levels <- c(unname(ROLE_LABELS), POOL_LABEL)
who_cols <- setNames(c(DK_ACCENT2, DK_ACCENT, "#c98500", DK_POOL), who_levels)
sc$who <- factor(sc$who, levels = who_levels[who_levels %in% sc$who])

n_roster <- sum(sc$who != POOL_LABEL)
message(nrow(sc), " midfielders in the pool, ", n_roster, " from the ", CLUB, " roster")

# ---- labels: whole roster + the league's top creators ----------------------
others <- sc |> filter(who == POOL_LABEL)
top_ids <- others$player_id[order(-others$kp90)][seq_len(min(N_TOP_LABELS, nrow(others)))]
labeled <- sc |>
  filter(who != POOL_LABEL | player_id %in% top_ids) |>
  mutate(name_label = ifelse(role == "departed",
                             paste0(player_name, " (departed)"), player_name))

# ---- chart ------------------------------------------------------------------
med_d <- median(sc$def90); med_k <- median(sc$kp90)
xr <- range(sc$def90); yr <- range(sc$kp90)
corner <- function(x, y, label, hjust, vjust) {
  annotate("text", x = x, y = y, label = label, hjust = hjust, vjust = vjust,
           size = 2.8, colour = DK_TEXT_2, fontface = "italic", family = FONT)
}
caption <- chart_footer(paste0(
  "Pool: ", POOL_LABEL, ", ", SEASON, ", min. 600 league minutes. ",
  "Dashed lines mark pool medians"
))

p <- ggplot(sc, aes(x = def90, y = kp90)) +
  geom_hline(yintercept = med_k, colour = DK_GRID, linetype = "dashed",
             linewidth = 0.4) +
  geom_vline(xintercept = med_d, colour = DK_GRID, linetype = "dashed",
             linewidth = 0.4) +
  corner(xr[2], yr[2], "Creates and wins it", 1, 1) +
  corner(xr[1], yr[2], "Creator", 0, 1) +
  corner(xr[2], yr[1], "Destroyer", 1, 0) +
  # context first, roster on top, biggest mark for the departed player
  geom_point(data = filter(sc, who == POOL_LABEL), aes(fill = who),
             size = 2.4, shape = 21, colour = DK_INK, stroke = 0.4, alpha = 0.8) +
  geom_point(data = filter(sc, who != POOL_LABEL, role != "departed"),
             aes(fill = who),
             size = 3.6, shape = 21, colour = DK_INK, stroke = 0.6) +
  geom_point(data = filter(sc, role == "departed"), aes(fill = who),
             size = 4.6, shape = 21, colour = DK_INK, stroke = 0.7) +
  ggrepel::geom_text_repel(
    data = labeled, aes(label = name_label),
    size = 3, colour = DK_TEXT, family = FONT, seed = 7,
    segment.colour = DK_GRID, min.segment.length = 0.2, box.padding = 0.4,
    max.overlaps = Inf
  ) +
  scale_fill_manual(values = who_cols, breaks = levels(sc$who)) +
  guides(fill = guide_legend(override.aes = list(size = 3.2, alpha = 1))) +
  labs(
    title = TITLE_MAP,
    subtitle = paste0("Defensive work vs. chance creation - ", POOL_LABEL, ", ",
                      SEASON, ". ", CLUB, "'s central midfielders by role"),
    x = "Tackles + interceptions per 90", y = "Key passes per 90",
    caption = caption
  ) +
  theme_pitchside_dark() +
  theme(
    plot.background  = element_rect(fill = MT_SURFACE, colour = NA),
    panel.background = element_rect(fill = MT_SURFACE, colour = NA)
  )

save_fig("figures/midfield_map.png", p, width = 10, height = 7.5,
         bg = MT_SURFACE)
