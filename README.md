# Polls vs. Cash

**Live site:** https://daniel-a-n-goldstein.github.io/pollsvscash/

A daily tracker of the **wedge** between what prediction markets price and what
the polls imply, for the 2026 U.S. midterms. Markets above polls = the money is
more hopeful than the data. Markets below = more doubtful.

The wedge bundles together things that are hard to separate: genuine
information the polls miss, systematic polling error the market anticipates,
thin liquidity, and plain wishful thinking by bettors. The site makes no claim
about which is which — it just shows the gap and tracks it daily. See the
[methods page](https://daniel-a-n-goldstein.github.io/pollsvscash/methods.html)
for the assumptions.

## How it works

```
pipeline/races.csv       which markets are tracked (Polymarket slugs / Kalshi tickers)
pipeline/polls.csv       poll benchmarks, with source notes — updated by hand
pipeline/update_data.R   pulls market prices, computes the wedge, writes docs/data.json
docs/                    the site (static HTML, served by GitHub Pages)
.github/workflows/       runs the pipeline daily at 06:30 UTC and commits the result
```

- **Market prices** are last-trade prices from the Polymarket Gamma API and the
  Kalshi API. No liquidity weighting; thin markets can show noisy numbers.
- **Poll-implied probabilities** come either straight from a published model or
  from a polling margin converted via a normal error model
  (`pnorm(margin / sigma)`, sigma = 5.5 points).
- **Wedge** = market − polls, in percentage points.

Data is in [`docs/data.json`](docs/data.json) if you want to use it; a daily
history per race is kept for up to a year.

Built by [Daniel Goldstein](https://github.com/daniel-a-n-goldstein).
