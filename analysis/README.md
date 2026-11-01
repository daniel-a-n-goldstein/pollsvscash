# Post-election analysis

Two scripts, run on demand via the "Run post-election analysis" workflow (Actions tab) or locally with `Rscript`.
Both read the site's own data and write to `analysis/output/`.

- `decomposition.R` — who closed the gap? Splits each race's change in wedge between launch (Oct 9) and election
  eve (Nov 2) into market movement and poll-benchmark movement, and splits day-to-day changes into poll-update
  days vs. market-only days.
- `event_study.R` — does the money move before the poll? Uses the daily snapshots in `pipeline/polls_raw/` to date
  each poll's release (first snapshot it appears in) and measures the market's move, signed toward the poll's
  direction, in the days before and after. Descriptive: a few dozen releases, pooled.

Cadence caveat: the market series is daily; the poll benchmark is RCP's average, refreshed weekly, so it is a step
series and smoother by construction. Net launch-to-eve changes and the event study (which dates poll *releases*
daily from the snapshots) are unaffected; raw "total movement" comparisons are biased toward the market.

Outputs are CSVs plus one PNG each. Rerun after Nov 2 for the final numbers.
