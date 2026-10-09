# ------------------------------------------------------------------
# Polls vs. Cash — daily data pipeline
# Pulls market prices from Polymarket / Kalshi, reads poll benchmarks
# from pipeline/polls.csv, computes the wedge, and appends today's
# snapshot to docs/data.json (which the website reads).
#
# Run locally with:  Rscript pipeline/update_data.R
# Runs automatically via .github/workflows/update.yml
# Only dependency: jsonlite
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

races <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
polls <- read.csv("pipeline/polls.csv",  stringsAsFactors = FALSE)

today <- format(Sys.Date(), "%Y-%m-%d")

# ---- helpers ------------------------------------------------------

# Convert a poll margin (in points, for the side the market is about)
# into a win probability using a normal model of historical polling
# error. sigma = 5.5 is a reasonable default for state-level polls
# a few months out; tighten it closer to the election if you like.
margin_to_prob <- function(margin, sigma = 5.5) {
  round(100 * pnorm(margin / sigma), 1)
}

fetch_polymarket <- function(slug, outcome) {
  url <- paste0("https://gamma-api.polymarket.com/markets?slug=", slug)
  m <- tryCatch(fromJSON(url), error = function(e) NULL)
  if (is.null(m) || length(m) == 0) return(NA_real_)
  outcomes <- fromJSON(m$outcomes[1])
  prices   <- as.numeric(fromJSON(m$outcomePrices[1]))
  idx <- match(tolower(outcome), tolower(outcomes))
  if (is.na(idx)) return(NA_real_)
  p <- round(100 * prices[idx], 1)
  # best bid/ask are quoted for the first (Yes) outcome; flip for No
  bid <- suppressWarnings(as.numeric(m$bestBid[1])); ask <- suppressWarnings(as.numeric(m$bestAsk[1]))
  if (idx != 1 && !is.na(bid) && !is.na(ask)) { tmp <- bid; bid <- 1 - ask; ask <- 1 - tmp }
  attr(p, "bid") <- if (is.na(bid)) NA else round(100 * bid, 1)
  attr(p, "ask") <- if (is.na(ask)) NA else round(100 * ask, 1)
  p
}

fetch_kalshi <- function(ticker, outcome = "yes") {
  url <- paste0("https://api.elections.kalshi.com/trade-api/v2/markets/", ticker)
  m <- tryCatch(fromJSON(url), error = function(e) NULL)
  if (is.null(m$market)) return(NA_real_)
  # last_price is in cents for the YES side
  p <- as.numeric(m$market$last_price)
  if (tolower(outcome) == "no") p <- 100 - p
  round(p, 1)
}

# ---- load existing history ---------------------------------------

data_path <- "docs/data.json"
old <- if (file.exists(data_path)) fromJSON(data_path, simplifyVector = FALSE) else list(races = list())
old_by_id <- setNames(old$races, vapply(old$races, function(r) r$id, ""))

# ---- build today's snapshot --------------------------------------

out_races <- lapply(seq_len(nrow(races)), function(i) {
  r <- races[i, ]

  market_prob <- switch(r$source,
    polymarket = fetch_polymarket(r$identifier, r$outcome),
    kalshi     = fetch_kalshi(r$identifier, r$outcome),
    NA_real_
  )

  p <- polls[polls$id == r$id, ]
  poll_prob <- if (nrow(p) == 0) NA_real_
    else if (!is.na(p$poll_prob[1]) && p$poll_prob[1] != "") as.numeric(p$poll_prob[1])
    else if (!is.na(p$poll_margin[1]) && p$poll_margin[1] != "") margin_to_prob(as.numeric(p$poll_margin[1]))
    else NA_real_

  # carry over history; carry forward last price if today's fetch failed
  hist <- if (!is.null(old_by_id[[r$id]])) old_by_id[[r$id]]$history else list()
  if (is.na(market_prob) && length(hist) > 0) {
    market_prob <- hist[[length(hist)]]$market
    message("WARN: fetch failed for ", r$id, " — carrying forward last price")
  }

  # replace today's entry if the script runs twice in one day
  hist <- Filter(function(h) h$date != today, hist)
  pt <- list(date = today, market = as.numeric(market_prob), polls = poll_prob)
  if (!is.null(attr(market_prob, "bid")) && !is.na(attr(market_prob, "bid"))) {
    pt$bid <- attr(market_prob, "bid"); pt$ask <- attr(market_prob, "ask")
  }
  hist <- c(hist, list(pt))
  # keep at most 365 days
  if (length(hist) > 365) hist <- tail(hist, 365)

  list(
    id     = r$id,
    name   = r$name,
    sub    = r$sub,
    market = as.numeric(market_prob),
    polls  = poll_prob,
    sigma  = 5.5,
    poll_note = if (nrow(p) > 0 && "note" %in% names(p)) p$note[1] else "",
    result = if ("result" %in% names(r) && !is.na(r$result) && nzchar(r$result)) r$result else NULL,
    wedge  = round(as.numeric(market_prob) - poll_prob, 1),
    history = hist
  )
})

result <- list(updated = today, races = out_races)
write_json(result, data_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
message("Wrote ", data_path, " — ", length(out_races), " races, ", today)
