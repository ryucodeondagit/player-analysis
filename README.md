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
scraping/06_scrape_chelsea_midfield.py
                                Chelsea midfield roster (MIDFIELD_ROSTER):
                                ids, 25/26 stats + season heatmaps, plus
                                the PL 25/26 leaderboard/squad caches
scraping/07_build_midfield_pool.py
                                PL midfielder pool -> pool_pl_midfielders.csv
R/viz_common.R                  shared: packages, design tokens, theme,
                                pitch drawing (sourced, not run)
R/comparisons.R                 percentile bars, pool distributions,
                                tackles-vs-interceptions scatter
R/heatmaps.R                    pitch heatmaps: Serie A seasons side by
                                side + 25/26 all competitions
R/club_comparison.R             Ahanor vs COMPARE_CLUB's CB room, dot-range
                                chart on an all-ages percentile scale
R/midfield_creation_share.R     Chelsea midfield: who created (100% stacked
                                bars, Enzo vs the rest)
R/midfield_scatter.R            Chelsea midfield: defensive work vs key
                                passes, PL midfielders, roster highlighted
R/midfield_heatmaps.R           Chelsea midfield: one pitch per roster
                                player, 25/26 season heatmaps
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

## Chelsea midfield: can it survive without Enzo?

A second, squad-level analysis on the same scraper. The question is whether
Chelsea's central midfield keeps a chance creator after Enzo Fernández's
transfer, now that the Camara deal is off. The evidence base is the last
full season (25/26). Nothing in the Ahanor pipeline is touched; the new
scripts reuse the client, the parsing functions and the R design tokens.

The roster is configured by **name** in `MIDFIELD_ROSTER` (`sofascore.py`),
each with a role: `departed`, `stays`, `new signing`. Names resolve to
Sofascore ids at scrape time - Chelsea's current squad first, then
Sofascore search (that is how the departed player still resolves). If
search picks a namesake, pin the id in `MIDFIELD_PLAYER_IDS`. The two new
signings are taken to be Valentín Barco and Jordan Henderson - edit the
roster if that is wrong. Cole Palmer is deliberately not on it: he is a
10/winger, and the question is about the central trio.

Each roster player's evidence is his 25/26 league season: Premier League
if he has one, otherwise any Big-5 league (a signing bought from abroad
brings his own league's heatmap). Players without a 25/26 Premier League
row stay out of the scatter but keep their heatmap panel.

```sh
python scraping/06_scrape_chelsea_midfield.py  # ~40 requests + PL caches if missing
python scraping/07_build_midfield_pool.py      # offline join/filter
Rscript R/midfield_creation_share.R            # figures/midfield_creation_share.png
Rscript R/midfield_scatter.R                   # figures/midfield_map.png
Rscript R/midfield_heatmaps.R                  # figures/midfield_heatmaps.png
```

If `03` already ran, `06` reuses its `peer_stats_premier-league_25-26.csv`
and `squads_premier-league.csv`; otherwise it scrapes just those two
(~30 requests). Sofascore's search endpoint (`/search/all`) is used for the
first time here - if it comes back in a shape `parse_search_players` does
not recognise, the script says which names failed and how to pin them.

The three charts, and what each is for:

* **Creation share** - one 100% stacked bar per metric (minutes first,
  then key passes, big chances created, xA, assists), split by player. If
  the departed player's creation share is far above his minutes share, the
  hole is the creation itself, not one starter's minutes. The subtitle
  states that comparison from the data.
* **Midfield map** - every PL midfielder (600+ min) by tackles +
  interceptions per 90 (x) and key passes per 90 (y). Roster players are
  coloured by role; the league's top creators are named for context. The
  message is the shape: where the remaining blue dots sit, and whether any
  of them sits near the orange one.
* **Heatmap grid** - one pitch per roster player, departed first, new
  signings last on their own 25/26 league. Panel strips carry role, league
  and minutes.

The R scripts use "·" in labels; run them under a UTF-8 locale (the
default on current R/Windows; on a minimal Linux set `LANG=C.UTF-8`).

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
