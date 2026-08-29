# Honest Ahanor — player analysis

Data scraping + analysis of Atalanta defender **Honest Ahanor** (b. 2008-02-23,
signed from Genoa in July 2025), built in R. End goals: touch heatmaps,
comparison charts vs his age range across the Big 5 leagues, and head-to-head
player comparisons.

## Data sources

| What | Source | Script | Technique |
|---|---|---|---|
| Season stats, match logs, scouting percentiles, Big-5 peer pool | [FBref](https://fbref.com/en/players/42ff58c3/Honest-Ahanor) | `R/01_scrape_fbref.R` | `worldfootballR` (rvest HTML tables) |
| Per-match touch heatmap coordinates | [Sofascore](https://www.sofascore.com/football/player/honest-ahanor/1634980) | `R/02_scrape_sofascore.R` | `httr2` against the site's own JSON endpoints |

FBref has no coordinate data, and StatsBomb's free event data doesn't cover
Serie A 2025-26, so Sofascore's (unofficial) JSON API is the practical open
source for heatmaps. That endpoint is undocumented: keep the built-in
throttle, expect it to change shape someday, and treat it as
personal-project-only.

## Running the scrapers

```sh
Rscript R/01_scrape_fbref.R      # slow on purpose: ~7s pause between requests
Rscript R/02_scrape_sofascore.R
```

Both scripts install missing packages on first run, write results to
`data/raw/` as `.rds` (plus `.csv` twins for eyeballing), and **skip anything
already on disk** — scrape once, then work from disk. Force a re-scrape with:

```sh
FORCE_REFRESH=1 Rscript R/01_scrape_fbref.R
```

All shared constants (player IDs, season years, cutoff dates, pause lengths)
live in `R/00_setup.R`.

### Rate limits, or: why the FBref script takes minutes

FBref temp-bans IPs exceeding roughly 10 requests/minute (bans last ~24h).
The scripts pause 7s between FBref calls and throttle Sofascore to
~12 requests/minute. Don't shorten these.

### Things to verify on first run

These scripts were written without live access to the sites (authored in a
sandbox whose network policy blocks them), so two spots are coded defensively
and worth a glance on your first local run:

1. **Sofascore heatmap JSON shape** — the point list has appeared under both
   `heatmap` and `points` keys across API versions; `parse_heatmap()` in
   `R/02_scrape_sofascore.R` accepts both. If every match comes back with 0
   points, print one raw response body and adjust that function.
2. **worldfootballR column names** — FBref occasionally renames columns;
   if a downstream script complains, check `names()` of the freshly scraped
   data frames.

## Repo layout

```
R/00_setup.R              constants, caching helpers, polite-scraping config
R/01_scrape_fbref.R       FBref: player stats + Big-5 age-peer pool
R/02_scrape_sofascore.R   Sofascore: per-match heatmap point clouds
data/raw/                 scraped output (gitignored; re-creatable)
```

Planned next (not yet written):

```
R/03_build_peer_pool.R    filter Big-5 pool to young defenders, percentiles
R/04_viz_heatmap.R        ggsoccer pitch + density heatmaps
R/05_viz_comparisons.R    age-range percentile charts, head-to-head radars
```
