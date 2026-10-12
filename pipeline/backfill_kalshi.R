# ------------------------------------------------------------------
# Polls vs. Cash — one-off Kalshi history backfill
#
# For every race with a kalshi_ticker in races.csv, pull daily candles
# from Kalshi's public API and add market_kalshi (bid-ask midpoint at
# the daily close) to the rows already in docs/data.json. Rows are
# matched by date; no rows are added or removed, and the Polymarket
# series is untouched. Safe to re-run.
#
# Run via .github/workflows/backfill-kalshi.yml (manual trigger) or:
#   Rscript pipeline/backfill_kalshi.R
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

START <- as.Date("2026-08-15")

races <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
data_path <- "docs/data.json"
old <- fromJSON(data_path, simplifyVector = FALSE)

num <- function(x) suppressWarnings(as.numeric(x))
ts  <- function(d) as.numeric(as.POSIXct(paste(d, "00:00:00"), tz = "UTC"))

fetch_kalshi_history <- function(ticker) {
  series <- sub("-.*$", "", ticker)                     # SENATEAK-26-D -> SENATEAK
  url <- sprintf("https://api.elections.kalshi.com/trade-api/v2/series/%s/markets/%s/candlesticks?start_ts=%d&end_ts=%d&period_interval=1440",
                 series, ticker, as.integer(ts(START)), as.integer(ts(Sys.Date() + 1)))
  h <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(h$candlesticks) || length(h$candlesticks) == 0) return(NULL)
  rows <- lapply(h$candlesticks, function(c) {
    bid <- if (!is.null(c$yes_bid$close_dollars)) 100 * num(c$yes_bid$close_dollars) else num(c$yes_bid$close)
    ask <- if (!is.null(c$yes_ask$close_dollars)) 100 * num(c$yes_ask$close_dollars) else num(c$yes_ask$close)
    if (length(bid) == 0 || length(ask) == 0 || is.na(bid) || is.na(ask)) return(NULL)
    # a candle's end_period_ts is the start of the NEXT day; the close belongs to the day before
    list(date = format(as.Date(as.POSIXct(c$end_period_ts, origin = "1970-01-01", tz = "UTC")) - 1),
         mid = round((bid + ask) / 2, 1), bid = round(bid, 1), ask = round(ask, 1))
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(NULL)
  setNames(rows, vapply(rows, function(x) x$date, ""))
}

old$races <- lapply(old$races, function(r) {
  meta <- races[races$id == r$id, ]
  tk <- if (nrow(meta) && "kalshi_ticker" %in% names(meta)) meta$kalshi_ticker else ""
  if (is.na(tk) || !nzchar(tk)) return(r)
  kh <- fetch_kalshi_history(tk)
  if (is.null(kh)) { message("WARN: no Kalshi history for ", r$id, " (", tk, ")"); return(r) }
  n <- 0
  r$history <- lapply(r$history, function(h) {
    k <- kh[[h$date]]
    if (!is.null(k)) { h$market_kalshi <- k$mid; h$kalshi_bid <- k$bid; h$kalshi_ask <- k$ask; n <<- n + 1 }
    h
  })
  message(r$id, ": Kalshi filled on ", n, " of ", length(r$history), " days")
  r
})

write_json(old, data_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
message("Wrote ", data_path)
