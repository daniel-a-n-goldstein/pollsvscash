# Polls vs. Cash

**Live site:** https://daniel-a-n-goldstein.github.io/pollsvscash/

A daily tracker of the **wedge** between prediction markets and polls for the 2026 U.S. midterms. Every race is read from the Democratic side: a positive wedge means the money leans more Democratic than the polls, a negative one more Republican. When the wedge is non-zero, someone with money on
the line is betting the polls are wrong.

The wedge bundles together genuine information the polls miss, systematic polling error the market anticipates, thin liquidity, and plain wishful thinking by bettors, but does not differentiate these factors. See the
[methods page](https://daniel-a-n-goldstein.github.io/pollsvscash/methods.html)
for the assumptions.

## How it works

```
pipeline/races.csv        which markets are tracked (Polymarket slugs) and which RCP race id benchmarks each
pipeline/update_polls.R   weekly: fetches RealClearPolling averages into pipeline/polls.csv
pipeline/polls_manual.csv benchmarks that have no RCP average (chamber control uses a model probability)
pipeline/update_data.R    daily: pulls market prices, computes the wedge, writes docs/data.json
pipeline/archive_polls.R  daily: snapshots the individual polls behind each RCP average into pipeline/polls_raw/
docs/                     the site: index.html (tracker), methods.html, results.html (post-election scorecard)
analysis/                 post-election scripts: who closed the gap, and an event study around poll releases
.github/workflows/        daily market run (morning UTC, afternoon backstop), weekly poll refresh (Sundays), manual analysis run
```

- **Market prices** are the midpoint of the best bid and best ask, which are read once a
  day from the market's public API (Polymarket). There is no liquidity weighting.
- **Second venue.** Each race also records Kalshi's midpoint (`market_kalshi`).
- **Poll-implied probabilities** come from the RealClearPolling average for each
  race (refreshed weekly), converted to a win probability via a normal error model
  (`pnorm(margin / sigma)`, sigma = 5.5 points). The House row uses the RCP
  generic-ballot average, which is a loose proxy for chamber control. Senate
  control has no polling margin, so it uses a published model probability,
  entered by hand and dated in `polls_manual.csv`.
- **Wedge** = market − polls, in percentage points.

Data is in [`docs/data.json`](docs/data.json); a daily
history per race is kept for up to a year.

Write-ups posted along the way are in [`notes/`](notes/).

Built by [Daniel A. N. Goldstein](https://daniel-a-n-goldstein.com), University of Oslo.
