# Player analysis — Sofascore scraper + R charts

Two analyses on one scraper. The data lands as plain CSV in `data/raw/`,
the charts are R (ggplot2) on top of it.

1. **A single-player analysis** (scripts 01–05, `R/comparisons.R`,
   `R/heatmaps.R`, `R/club_comparison.R`, `R/leftfoot_scatter.R`). The
   subject is configured in `scraping/sofascore.py` — currently
   **Valentín Barco** (left-back, b. 2004-07-23; Sevilla and Strasbourg
   loans in 24/25, Strasbourg in 25/26, Chelsea from summer 2026). The
   pipeline was first built for Honest Ahanor (Atalanta centre-back); the
   subject block below is all that changed to re-point it.
2. **The Chelsea midfield question** (scripts 06–07, `R/midfield_*.R`) —
   see the section further down.

## Pointing the player analysis at a subject

Four lines in `scraping/sofascore.py`:

```python
PLAYER_NAME = "Valentín Barco"
PLAYER_ID = None            # None = resolved by Sofascore search on the first run of 01
PLAYER_POSITION = "D"       # Sofascore's coarse position -> the comparison pool
ROLE_CODES = {"LB", "DL", "LWB", "RB", "DR", "RWB"}   # detailed codes = "same role"
ROLE_LABEL = "full-backs"
```

Plus two hand-kept labels in `R/viz_common.R`: `SEASON_TEAMS` (club per
season, for the pizza titles — Sofascore's season stats carry no club) and
`ROLE_LABEL` / `POSITION_LABEL`. The metric set (`METRICS` in
`R/viz_common.R`) is a full-back's job description — defend, win duels,
progress and create; swap it for another role. After changing the subject,
delete the subject files in `data/raw/` (everything except the
`peer_stats_*`, `squads_*` and `characteristics.csv` caches, which are
league-wide and reusable).

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
scraping/01_scrape_player.py    resolves PLAYER_NAME -> id (search, cached in
                                subject.json); bio, seasons list, per-season stats
scraping/02_scrape_heatmaps.py  match list, per-match heatmap points,
                                season-aggregate heatmaps
scraping/03_scrape_peer_pool.py ALL Big-5 leagues: leaderboard stats +
                                squad birth dates (per-league caches)
scraping/04_build_pool.py       join + filter -> pool_u23.csv (U23, 600+ min,
                                per-90s, is_role tag) and pool_all.csv (any age)
scraping/05_scrape_club_role.py COMPARE_CLUB's same-role players -> club_role.csv
scraping/06_scrape_chelsea_midfield.py
                                Chelsea midfield roster (MIDFIELD_ROSTER):
                                ids, 25/26 stats + season heatmaps, plus
                                the PL 25/26 leaderboard/squad caches
scraping/07_build_midfield_pool.py
                                PL midfielder pool -> pool_pl_midfielders.csv
R/viz_common.R                  shared: packages, design tokens, theme,
                                pitch drawing (sourced, not run)
R/comparisons.R                 percentile pizzas, pool distributions,
                                two-way scatter (SCATTER_X vs SCATTER_Y)
R/heatmaps.R                    pitch heatmaps: one panel per league season
                                + 25/26 all competitions
R/club_comparison.R             subject vs COMPARE_CLUB's same-role room,
                                dot-range chart on an all-ages percentile scale
R/leftfoot_scatter.R            left-footed market: interceptions vs tackles,
                                any age, subject highlighted
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
python scraping/05_scrape_club_role.py   # a handful of requests, cached
Rscript R/comparisons.R                  # needs R with ggplot2 etc. (auto-installs)
Rscript R/heatmaps.R                     # pitch heatmaps -> figures/
Rscript R/club_comparison.R              # the club-fit chart -> figures/
Rscript R/leftfoot_scatter.R             # the left-footed market -> figures/
python tests/test_parsing.py             # offline sanity check, no network
```

**Both seasons in `SEASONS` are in scope** (24/25 and 25/26). The subject's
stats and season heatmaps cover every season Sofascore has for him,
per-match heatmaps go back to `CUTOFF_DATE`, and the peer pool is scraped
per season. The pool is every **Big-5 player of `PLAYER_POSITION` under
23** (age measured at each season's own end, so both seasons compare
like-for-like) with 600+ league minutes; the subject's own rows always
survive the filters. `04` additionally tags the subject's role via each
player's characteristics endpoint (the only place Sofascore separates
full-back from centre-back — the leaderboard just says "D") using
`ROLE_CODES`. The R script computes percentiles within each season's own
pool, charts both seasons side by side, and prefers the role-tagged pool,
falling back to the whole position if tagging came back thin. A player
with two league rows in one season (a mid-season move — Barco's 24/25)
keeps the row with more minutes in the percentile charts; the heatmap
script shows both leagues as separate panels. Cutoffs live in
`scraping/sofascore.py` (`AGE_MAX`, `MIN_MINUTES`, `SEASONS`); changing
them only requires re-running `04` and the R script — never a re-scrape.

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
full season (25/26). Nothing in the single-player pipeline is touched; the new
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
