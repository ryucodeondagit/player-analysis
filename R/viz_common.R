# viz_common.R ----------------------------------------------------------------
# Shared bits for all chart scripts: package install, design tokens, theme,
# and the football pitch drawing (Opta/Sofascore 0-100 x 0-100 space).
# Sourced by comparisons.R and heatmaps.R - not run directly.

required <- c("readr", "dplyr", "tidyr", "ggplot2", "scales", "ggrepel",
              "systemfonts", "ragg")
to_install <- setdiff(required, rownames(installed.packages()))
# explicit repos: non-interactive Rscript has no CRAN mirror configured
if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
}
library(dplyr)
library(tidyr)
library(ggplot2)

PLAYER_ID <- 1634980
CURRENT_SEASON <- "25/26"

# Footer credit on every figure - put your name/handle here (or leave "").
AUTHOR <- ""

# ---- typography --------------------------------------------------------------
# First installed font from this list wins; "" falls back to the device sans.
# Add your favourite to the front (e.g. "Inter" if you've installed it).
pick_font <- function(candidates = c("Inter", "Roboto Condensed", "Roboto",
                                     "Segoe UI", "Helvetica Neue")) {
  installed <- tryCatch(unique(systemfonts::system_fonts()$family),
                        error = function(e) character())
  hit <- candidates[candidates %in% installed]
  if (length(hit) > 0) hit[1] else ""
}
FONT <- pick_font()

# one consistent source line for every chart
chart_footer <- function(note = NULL) {
  parts <- c(note, "Data: Sofascore", format(Sys.Date(), "%b %Y"),
             if (nzchar(AUTHOR)) AUTHOR)
  paste(parts, collapse = "  ·  ")
}

# high-res export through ragg (crisper text than the default device)
save_fig <- function(filename, plot, width, height, bg = COL_SURFACE) {
  dir.create("figures", showWarnings = FALSE)
  ggsave(filename, plot, width = width, height = height, dpi = 300,
         bg = bg, device = ragg::agg_png)
  message("saved ", filename)
}

# ---- design tokens (light surface; accent validated 3:1+) -------------------
COL_SURFACE <- "#fcfcfb"
COL_TEXT    <- "#0b0b0b"
COL_TEXT_2  <- "#52514e"
COL_GRID    <- "#e8e7e3"
COL_ACCENT  <- "#2a78d6"  # Ahanor / primary series (categorical slot 1)
COL_ACCENT2 <- "#eb6834"  # secondary series (categorical slot 2)
COL_POOL    <- "#8f8d84"  # neutral context marks
# sequential blue ramp endpoints (magnitude encoding, one hue light->dark)
COL_SEQ_LO  <- "#cde2fb"
COL_SEQ_HI  <- "#0d366b"

# ---- dark-surface tokens (validated against this surface, not a hue flip) ---
DK_SURFACE <- "#1a1a19"
DK_TEXT    <- "#ffffff"
DK_TEXT_2  <- "#c3c2b7"
DK_GRID    <- "#383835"
DK_BORDER  <- "#4a4a46"  # panel frames - the "inked border" of the house style
DK_INK     <- "#121211"  # outline drawn around filled marks (reads as a gap)
DK_POOL    <- "#8f8d84"  # neutral context marks
DK_ACCENT  <- "#3987e5"  # categorical slot 1, dark step
DK_ACCENT2 <- "#d95926"  # categorical slot 2, dark step
# sequential blue for dark surfaces (dim near-surface -> bright)
DK_SEQ_LO  <- "#184f95"
DK_SEQ_HI  <- "#9ec5f4"
# metric families, fixed order (validated 4-slot set on the dark surface)
FAMILY_COLS <- c(
  "Overall"     = "#3987e5",
  "Defending"   = "#d95926",
  "Duels"       = "#199e70",
  "On the ball" = "#c98500"
)

theme_pitchside <- function() {
  theme_minimal(base_size = 12, base_family = FONT) +
    theme(
      plot.background = element_rect(fill = COL_SURFACE, colour = NA),
      panel.background = element_rect(fill = COL_SURFACE, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = COL_GRID, linewidth = 0.4),
      text = element_text(colour = COL_TEXT),
      axis.text = element_text(colour = COL_TEXT_2, size = 9),
      axis.title = element_text(colour = COL_TEXT_2, size = 10),
      # editorial layout: title block aligned to the plot edge, not the panel
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.title = element_text(face = "bold", size = 17,
                                margin = margin(b = 4)),
      plot.subtitle = element_text(colour = COL_TEXT_2, size = 10.5,
                                   margin = margin(b = 14)),
      plot.caption = element_text(colour = COL_TEXT_2, size = 8, hjust = 1,
                                  margin = margin(t = 14)),
      plot.margin = margin(18, 22, 14, 22),
      strip.text = element_text(colour = COL_TEXT_2, size = 9.5,
                                face = "bold"),
      legend.position = "top",
      legend.justification = "left",
      legend.title = element_blank(),
      legend.text = element_text(size = 9.5)
    )
}

theme_pitchside_dark <- function() {
  theme_pitchside() +
    theme(
      plot.background = element_rect(fill = DK_SURFACE, colour = NA),
      panel.background = element_rect(fill = DK_SURFACE, colour = NA),
      panel.grid.major = element_line(colour = DK_GRID, linewidth = 0.4),
      text = element_text(colour = DK_TEXT),
      axis.text = element_text(colour = DK_TEXT_2),
      axis.title = element_text(colour = DK_TEXT_2),
      plot.title = element_text(colour = DK_TEXT, face = "bold", size = 17,
                                margin = margin(b = 4)),
      plot.subtitle = element_text(colour = DK_TEXT_2, size = 10.5,
                                   margin = margin(b = 14)),
      plot.caption = element_text(colour = DK_TEXT_2, size = 8, hjust = 1,
                                  margin = margin(t = 14)),
      strip.text = element_text(colour = DK_TEXT_2, size = 9.5, face = "bold"),
      legend.text = element_text(colour = DK_TEXT, size = 9.5),
      panel.border = element_rect(colour = DK_BORDER, fill = NA,
                                  linewidth = 0.6)
    )
}

# ---- shared metric config ---------------------------------------------------
# Metric column -> readable label; grouped into families for the bar/dot
# charts. "Lower is better" metrics get their percentile inverted so every
# chart reads "higher = better".
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

# ---- pitch drawing ----------------------------------------------------------
# Sofascore points live in a 0-100 x 0-100 space (Opta convention, attacking
# left to right). Drawn with plain annotations - no extra package needed.
# Real-world proportions come from coord_fixed(68 / 105) on the plot; the
# centre "circle" is an ellipse in unit space so it renders circular.
ellipse_path <- function(cx, cy, rx, ry, n = 120) {
  t <- seq(0, 2 * pi, length.out = n)
  data.frame(x = cx + rx * cos(t), y = cy + ry * sin(t))
}

pitch_layers <- function(line_col = "#c2c1bb", linewidth = 0.4) {
  rx <- 9.15 / 105 * 100  # 9.15 m radius in x units
  ry <- 9.15 / 68 * 100   # ... and in y units
  box_x <- 16.5 / 105 * 100
  box_y <- c(50 - 40.32 / 68 * 50, 50 + 40.32 / 68 * 50)
  six_x <- 5.5 / 105 * 100
  six_y <- c(50 - 18.32 / 68 * 50, 50 + 18.32 / 68 * 50)
  spot_x <- 11 / 105 * 100

  list(
    annotate("rect", xmin = 0, xmax = 100, ymin = 0, ymax = 100,
             fill = NA, colour = line_col, linewidth = linewidth),
    annotate("segment", x = 50, xend = 50, y = 0, yend = 100,
             colour = line_col, linewidth = linewidth),
    geom_path(data = ellipse_path(50, 50, rx, ry), aes(x = x, y = y),
              colour = line_col, linewidth = linewidth, inherit.aes = FALSE),
    annotate("rect", xmin = 0, xmax = box_x, ymin = box_y[1], ymax = box_y[2],
             fill = NA, colour = line_col, linewidth = linewidth),
    annotate("rect", xmin = 100 - box_x, xmax = 100, ymin = box_y[1], ymax = box_y[2],
             fill = NA, colour = line_col, linewidth = linewidth),
    annotate("rect", xmin = 0, xmax = six_x, ymin = six_y[1], ymax = six_y[2],
             fill = NA, colour = line_col, linewidth = linewidth),
    annotate("rect", xmin = 100 - six_x, xmax = 100, ymin = six_y[1], ymax = six_y[2],
             fill = NA, colour = line_col, linewidth = linewidth),
    annotate("point", x = c(spot_x, 50, 100 - spot_x), y = c(50, 50, 50),
             colour = line_col, size = 0.6)
  )
}

theme_pitch <- function() {
  theme_pitchside_dark() +
    theme(
      panel.grid = element_blank(),
      axis.text = element_blank(),
      axis.title = element_blank(),
      panel.border = element_blank()  # the pitch outline is its own frame
    )
}

# matte charcoal surface, a step lighter than DK_SURFACE - the pitch maps
# and the scatters sit on it. All DK_* marks were contrast-checked on it too.
MT_SURFACE <- "#252523"

# ---- heatmap layers ----------------------------------------------------------
# density surface: inferno ramp (deep purple -> yellow), fading to
# transparent at the low end so the pitch shows through outside the active
# zones. Multi-hue so the rings are easy to tell apart, monotonic in
# lightness so the order (cool = fringe, hot = home zone) reads at a glance.
heat_layers <- function() {
  list(
    stat_density_2d(
      geom = "polygon",
      aes(x = x, y = y, fill = after_stat(level), alpha = after_stat(level)),
      bins = 10, contour_var = "ndensity",
      # thin ink line between contour bands - each ring reads separately
      colour = "#121211", linewidth = 0.2
    ),
    scale_fill_viridis_c(option = "inferno", begin = 0.15, end = 0.95,
                         guide = "none"),
    scale_alpha_continuous(range = c(0.25, 0.95), guide = "none")
  )
}

# one pitch heatmap (facet it from the caller for small multiples).
# `points` needs x, y columns, already expanded by their count weight.
pitch_plot <- function(points, title, subtitle, caption, surface = MT_SURFACE) {
  ggplot(points) +
    heat_layers() +
    pitch_layers(line_col = "#55534e") +
    # direction-of-attack arrow in the strip below the pitch
    annotate("segment", x = 42, xend = 58, y = -5, yend = -5,
             colour = DK_TEXT_2, linewidth = 0.5,
             arrow = arrow(length = unit(5, "pt"), type = "closed")) +
    annotate("text", x = 60.5, y = -5, label = "Attack", hjust = 0,
             size = 2.9, colour = DK_TEXT_2, family = FONT) +
    coord_fixed(ratio = 68 / 105, xlim = c(0, 100), ylim = c(-9, 100),
                expand = FALSE) +
    labs(title = title, subtitle = subtitle, caption = caption) +
    theme_pitch() +
    theme(
      plot.background  = element_rect(fill = surface, colour = NA),
      panel.background = element_rect(fill = surface, colour = NA)
    )
}

