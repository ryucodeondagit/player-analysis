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
scraping/03_scrape_peer_pool.py Serie A leaderboard stats + squad birth
                                dates -> the age-comparison pool
tests/test_parsing.py           offline tests (mock JSON, no network)
data/raw/                       CSV output (gitignored; re-creatable)
```

## Running

```sh
pip install -r requirements.txt          # just `requests`
python scraping/01_scrape_player.py
python scraping/02_scrape_heatmaps.py    # run after 01 (uses its seasons list)
python scraping/03_scrape_peer_pool.py
python tests/test_parsing.py             # offline sanity check, no network
```

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
