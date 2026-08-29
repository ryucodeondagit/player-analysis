# Honest Ahanor — player analysis

Data scraping + analysis of Atalanta defender **Honest Ahanor** (b. 2008-02-23,
signed from Genoa in July 2025), built in R. End goals: touch heatmaps,
comparison charts vs his age range across the Big 5 leagues, and head-to-head
player comparisons.

## Data sources

| What | Source | Script | Technique |
|---|---|---|---|
| Season stats + Big-5 age-peer pool | [FBref](https://fbref.com/en/players/42ff58c3/Honest-Ahanor) data, via the maintainer's pre-scraped [worldfootballR data releases](https://github.com/JaseZiv/worldfootballR_data) | `R/01_scrape_fbref.R` | `worldfootballR` `load_*` functions (GitHub downloads — no request to fbref.com) |
| Match logs + scouting percentiles (best-effort) | FBref directly | `R/01_scrape_fbref.R` | `worldfootballR` scraping; usually blocked, skipped gracefully — see troubleshooting |
| Per-match touch heatmap coordinates | [Sofascore](https://www.sofascore.com/football/player/honest-ahanor/1634980) | `R/02_scrape_sofascore.R` | `httr2` against the site's own JSON endpoints |

FBref has no coordinate data, and StatsBomb's free event data doesn't cover
Serie A 2025-26, so Sofascore's (unofficial) JSON API is the practical open
source for heatmaps. That endpoint is undocumented: keep the built-in
throttle, expect it to change shape someday, and treat it as
personal-project-only.

## Running the scrapers

```sh
Rscript R/01_scrape_fbref.R      # fast: downloads pre-scraped data releases
Rscript R/02_scrape_sofascore.R  # throttled: ~12 requests/minute
```

Both scripts install missing packages on first run, write results to
`data/raw/` as `.rds` (plus `.csv` twins for eyeballing), and **skip anything
already on disk** — scrape once, then work from disk. Force a re-scrape with:

```sh
FORCE_REFRESH=1 Rscript R/01_scrape_fbref.R
```

All shared constants (player IDs, season years, cutoff dates, pause lengths)
live in `R/00_setup.R`.

### Troubleshooting: `Forbidden (HTTP 403)` from FBref

FBref's bot protection (Cloudflare) blocks scraper traffic outright — a 403
on the *first* request is their door policy, not a rate-limit ban, and no
amount of retrying fixes it. That's why `01_scrape_fbref.R` gets its core
data (Big-5 player tables, which include Ahanor's own rows) from the
[worldfootballR data releases](https://github.com/JaseZiv/worldfootballR_data)
instead: plain GitHub downloads, immune to the block.

The only pieces that still need fbref.com directly are the per-match logs
and the pre-built scouting report; the script attempts them, logs
`SKIPPED ... (HTTP 403)` when blocked, and carries on. If a run from some
network ever succeeds, the results are cached like everything else. Their
absence is covered: Sofascore provides per-match data, and
`03_build_peer_pool.R` computes percentiles from the Big-5 pool.

Also make sure worldfootballR came from GitHub, not CRAN (the CRAN build is
stale); `00_setup.R` installs it that way if it's missing:

```r
remotes::install_github("JaseZiv/worldfootballR")
```

### Rate limits

Sofascore is throttled to ~12 requests/minute; the direct-FBref attempts
pause 7s between calls (FBref temp-bans IPs exceeding ~10 requests/minute
for ~24h — relevant only if the 403 block ever lifts). Don't shorten either.

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
