# ------------------------------------------------------------------
# Polls vs. Cash — one-off poll history backfill (pre-launch only)
#
# RCP does not publish its historical averages, but its per-race feed
# lists every individual poll with field dates. For each pre-launch
# day (points flagged est = TRUE in docs/data.json) this script
# computes a transparent stand-in: the simple mean margin of polls
# whose field period ended in the trailing 28 days, widened to the
# most recent 3 polls whenever the window holds fewer than 3 (so a
# single outlier poll never becomes "the average").
# This is NOT RCP's average — expect a small seam at launch — and it
# is only ever applied to points already flagged est = TRUE.
#
# Run via .github/workflows/backfill.yml, after backfill_markets.R.
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

WINDOW <- 28
MIN_POLLS <- 3
SIGMA  <- 5.5

races <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
data_path <- "docs/data.json"
d <- fromJSON(data_path, simplifyVector = FALSE)

fetch_polls <- function(race_id, party) {
  url <- sprintf("https://orig.realclearpolitics.com/poll/race/%s/polling_data.json", race_id)
  j <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(NULL)
  rows <- lapply(j$poll, function(p) {
    if (identical(p$type, "rcp_average") || is.null(p$data_end_date)) return(NULL)
    side  <- Filter(function(c) identical(c$affiliation, party), p$candidate)
    other <- Filter(function(c) !identical(c$affiliation, party), p$candidate)
    if (length(side) != 1 || length(other) < 1) return(NULL)
    data.frame(end = as.Date(gsub("/", "-", p$data_end_date)),
               margin = as.numeric(side[[1]]$value) - max(vapply(other, function(c) as.numeric(c$value), 0)),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(out)) return(NULL)
  out[order(out$end), ]
}

est_margin <- function(polls, day) {
  elig <- polls[polls$end <= day, ]
  if (nrow(elig) == 0) return(NA_real_)
  win <- elig[elig$end > day - WINDOW, ]
  if (nrow(win) < MIN_POLLS) win <- tail(elig, MIN_POLLS)
  round(mean(win$margin), 1)
}

d$races <- lapply(d$races, function(r) {
  meta <- races[races$id == r$id, ]
  if (nrow(meta) == 0 || is.na(meta$rcp_id) || !nzchar(as.character(meta$rcp_id))) return(r)
  polls <- fetch_polls(meta$rcp_id, meta$poll_party)
  if (is.null(polls)) { message("WARN: no polls for ", r$id); return(r) }
  n <- 0
  r$history <- lapply(r$history, function(h) {
    if (!isTRUE(h$est)) return(h)
    m <- est_margin(polls, as.Date(h$date))
    if (is.na(m)) return(h)
    h$polls <- round(100 * pnorm(m / SIGMA), 1)
    h$poll_margin_est <- m
    n <<- n + 1
    h
  })
  message(r$id, ": estimated poll line on ", n, " pre-launch days from ", nrow(polls), " polls")
  r
})

write_json(d, data_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
message("Wrote ", data_path)
