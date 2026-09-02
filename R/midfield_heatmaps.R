# midfield_heatmaps.R ---------------------------------------------------------
# The empty zone: one pitch per Chelsea midfield-roster player, 25/26 season
# heatmaps side by side. The departed player's panel is first; new signings
# come last, on their own 25/26 league (wherever they played it).
#
# Reads  data/raw/chelsea_midfield_heatmaps.csv  (06_scrape_chelsea_midfield.py)
#        data/raw/chelsea_midfield_stats.csv     (minutes for the panel labels)
# Writes figures/midfield_heatmaps.png
#
# Run:  Rscript R/midfield_heatmaps.R

source("R/viz_common.R")

# ---- knobs: edit freely -----------------------------------------------------
TITLE_ZONES <- "The Zone Nobody Else Occupies"
SEASON      <- "25/26"
NCOL        <- 4

ROLE_ORDER  <- c("departed", "stays", "new signing")
ROLE_TEXT   <- c("departed" = "departed", "stays" = "stays",
                 "new signing" = "new signing")

# ---- data -------------------------------------------------------------------
points <- readr::read_csv("data/raw/chelsea_midfield_heatmaps.csv",
                          show_col_types = FALSE)
stats <- readr::read_csv("data/raw/chelsea_midfield_stats.csv",
                         show_col_types = FALSE) |>
  transmute(player_id,
            minutes = suppressWarnings(as.numeric(minutesPlayed)))

if (nrow(points) == 0) stop("no rows in chelsea_midfield_heatmaps.csv")

panels <- points |>
  distinct(player_id, player_name, role, tournament) |>
  left_join(stats, by = "player_id") |>
  mutate(
    role = factor(role, levels = ROLE_ORDER),
    # two short lines: the season is in the subtitle, so the strip only
    # carries role, league and minutes
    panel = paste0(
      player_name, "\n", ROLE_TEXT[as.character(role)], " · ", tournament,
      ifelse(is.na(minutes), "",
             paste0(" · ", trimws(format(round(minutes), big.mark = ",")), " min"))
    )
  ) |>
  arrange(role, desc(minutes))

heat <- points |>
  inner_join(select(panels, player_id, panel), by = "player_id") |>
  mutate(panel = factor(panel, levels = panels$panel)) |>
  uncount(weights = pmax(1, round(count)))

message(nrow(panels), " panels: ", paste(panels$player_name, collapse = ", "))

caption <- chart_footer("Sofascore 0-100 pitch coordinates, season aggregate")
departed <- panels$player_name[panels$role == "departed"]
subtitle <- paste0(
  "Season heatmaps, ", SEASON, ". ",
  if (length(departed) > 0) paste0(departed[1], "'s advanced half-space is the ",
                                   "zone to compare against. ") else "",
  "New signings shown on their own ", SEASON, " league"
)

p <- pitch_plot(heat, TITLE_ZONES, subtitle, caption) +
  facet_wrap(~panel, ncol = NCOL) +
  theme(
    strip.text = element_text(size = 8.5, colour = DK_TEXT, face = "bold",
                              lineheight = 1.1),
    panel.spacing = unit(8, "pt")
  )

nrow_panels <- ceiling(nrow(panels) / NCOL)
save_fig("figures/midfield_heatmaps.png", p, width = 3.7 * NCOL + 0.8,
         height = 2.75 * nrow_panels + 1.8, bg = MT_SURFACE)
