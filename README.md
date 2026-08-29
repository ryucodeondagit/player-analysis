# Honest Ahanor — player analysis

Data scraping + analysis of Atalanta defender **Honest Ahanor** (b. 2008-02-23,
signed from Genoa in July 2025). Scraping is Python; the data lands as plain
CSV in `data/raw/`, so the visualization layer (heatmaps, age-range comparison
charts, player comparisons) can be built in R or Python on top of it.

## Why Sofascore (and not FBref)

FBref would be the classic choice, but as of 2025/26 it's effectively closed
to scrapers: direct requests are rejected by its bot protection with
HTTP 403, and the community mirror of pre-scraped FBref data
(worldfootballR's data releases) stopped updating in October 2024 — before
Ahanor's breakout. Sofascore's JSON API (the same endpoints its own website
calls) is the practical open source that has everything we need: his bio and
season stats, per-match and per-season heatmap coordinates, and league-wide
player stats + squad birth dates for the age comparison pool.

Caveats: the API is unofficial (technically against Sofascore's ToS — fine
for a personal project at this volume, keep the built-in throttle), and
endpoint shapes can drift, which is why all response parsing lives in small
pure functions in `scraping/sofascore.py` with offline tests.

### Troubleshooting: HTTP 403 from Sofascore

Sofascore's bot protection fingerprints the TLS handshake itself, so plain
Python `requests` gets 403 regardless of headers. The client therefore uses
**curl_cffi** (impersonates a real Chrome fingerprint) — installed via
`requirements.txt` — and falls back across both API hosts
(`api.sofascore.com`, then `www.sofascore.com/api`). If you still see 403s:
confirm the venv is active and `pip show curl_cffi` finds it (the client
prints a warning at startup when it's missing); try again later (temporary
IP-level blocks happen); and if it's persistent, Sofascore has tightened
things again — the next escalation is driving a real browser (Playwright)
to fetch the same JSON URLs.

## Layout

```
scraping/sofascore.py           shared client (throttle, retries, headers)
                                + all parsing functions + constants
scraping/01_scrape_player.py    bio, seasons list, per-season statistics
scraping/02_scrape_heatmaps.py  match list, per-match heatmap points,
                                season-aggregate heatmaps
scraping/03_scrape_peer_pool.py ALL Big-5 leagues: leaderboard stats +
                                squad birth dates (per-league caches)
scraping/04_build_pool.py       join + filter -> pool_u23_defenders.csv
                                (U23, 600+ min, per-90s, is_cb tag) and
                                pool_defenders_all.csv (same, any age)
scraping/05_scrape_club_cbs.py  COMPARE_CLUB's centre-backs -> club_cbs.csv
R/viz_common.R                  shared: packages, design tokens, theme,
                                pitch drawing (sourced, not run)
R/comparisons.R                 percentile bars, pool distributions,
                                tackles-vs-interceptions scatter
R/heatmaps.R                    pitch heatmaps: Serie A seasons side by
                                side + 25/26 all competitions
R/club_comparison.R             Ahanor vs COMPARE_CLUB's CB room, dot-range
                                chart on an all-ages percentile scale
tests/test_parsing.py           offline tests (mock JSON, no network)
data/raw/                       CSV output (gitignored; re-creatable)
```

## Running

```sh
pip install -r requirements.txt          # curl_cffi + requests
python scraping/01_scrape_player.py
python scraping/02_scrape_heatmaps.py    # run after 01 (uses its seasons list)
python scraping/03_scrape_peer_pool.py   # ~160 requests, ~5 minutes
python scraping/04_build_pool.py         # join/filter + CB tagging
python scraping/05_scrape_club_cbs.py    # a handful of requests, cached
Rscript R/comparisons.R                  # needs R with ggplot2 etc. (auto-installs)
Rscript R/heatmaps.R                     # pitch heatmaps -> figures/
Rscript R/club_comparison.R              # the club-fit chart -> figures/
python tests/test_parsing.py             # offline sanity check, no network
```

**Both of Ahanor's seasons are in scope** (24/25 Genoa + 25/26 Atalanta —
`SEASONS` in `sofascore.py`): his stats and season heatmaps cover every
season Sofascore has for him, per-match heatmaps go back to July 2024, and
the peer pool is scraped per season. The pool is every **Big-5 defender
under 23** (age measured at each season's own end, so both seasons compare
like-for-like) with 600+ league minutes; Ahanor's own rows always survive
the filters. `04` additionally tags centre-backs via each player's
characteristics endpoint (the only place Sofascore separates CB from
full-back — the leaderboard just says "D"). The R script computes
percentiles within each season's own pool, charts both seasons side by
side, and prefers the CB-tagged pool, falling back to all young defenders
if tagging came back thin. Cutoffs live in `scraping/sofascore.py`
(`AGE_MAX`, `MIN_MINUTES`, `SEASONS`); changing them only requires
re-running `04` and the R script — never a re-scrape.

Scripts skip any output already in `data/raw/` — scrape once, work from
disk. Force a re-scrape with `FORCE_REFRESH=1` before the command (PowerShell:
`$env:FORCE_REFRESH="1"`), or delete files in `data/raw/`.

Requests are throttled to one per 1.5s with retry/backoff on 429/5xx.
Expect `02` to take a few minutes (one request per match). A 404 from a
heatmap is normal — it means no data for that player/match (unused sub).

## Notes on the data

* Coordinates are Sofascore's 0–100 × 0–100 pitch space, attacking
  left-to-right; per-match points carry a `count` weight.
* `peer_stats.csv` (season totals for every ranked Serie A player) joins
  `squads.csv` (birth dates, positions) on `player_id`; the analysis step
  computes ages and filters the comparison group (e.g. defenders born 2007+,
  500+ minutes) so changing the age cutoff never needs a re-scrape.
* Two spots are coded defensively against endpoint drift and worth a glance
  on first run: the heatmap point-list key (`heatmap` vs `points`, both
  handled) and the leaderboard `fields` list (falls back to a core subset on
  HTTP 400).

## What about `soccerdata`?

[probberechts/soccerdata](https://github.com/probberechts/soccerdata) was
evaluated: its Sofascore reader only covers league tables and schedules — no
player statistics and no heatmaps, so it can't feed this analysis. Its FBref
reader does work around the bot protection by driving a real Chrome browser
(`seleniumbase`), at the cost of heavy dependencies; it's a viable optional
add-on if FBref-grade stats (per-90s, Big-5-wide pool) are wanted later.
