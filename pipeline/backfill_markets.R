# ------------------------------------------------------------------
# Polls vs. Cash — one-off market history backfill
#
# For every Polymarket race in races.csv, pull the daily price history
# from Polymarket's CLOB API (fidelity = 1440 min = one point per day)
# and insert it into docs/data.json for dates before LAUNCH. Existing
# points on or after LAUNCH are left untouched. The poll value on
# backfilled days is held flat at the race's current benchmark and
# flagged est = TRUE so the site can draw it dashed.
#
# Run via .github/workflows/backfill.yml (manual trigger) or locally:
#   Rscript pipeline/backfill_markets.R
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

LAUNCH <- as.Date("2026-10-09")
START  <- as.Date("2026-08-15")

races <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
data_path <- "docs/data.json"
old <- fromJSON(data_path, simplifyVector = FALSE)
old_by_id <- setNames(old$races, vapply(old$races, function(r) r$id, ""))

fetch_history <- function(slug, outcome) {
  g <- tryCatch(fromJSON(paste0("https://gamma-api.polymarket.com/markets?slug=", slug)),
                error = function(e) NULL)
  if (is.null(g) || length(g) == 0) return(NULL)
  outcomes <- fromJSON(g$outcomes[1]); tokens <- fromJSON(g$clobTokenIds[1])
  tok <- tokens[match(tolower(outcome), tolower(outcomes))]
  h <- tryCatch(fromJSON(sprintf(
    "https://clob.polymarket.com/prices-history?market=%s&interval=max&fidelity=1440", tok)),
    error = function(e) NULL)
  if (is.null(h$history) || nrow(h$history) == 0) return(NULL)
  df <- data.frame(date = as.Date(as.POSIXct(h$history$t, origin = "1970-01-01", tz = "UTC")),
                   market = round(100 * h$history$p, 1))
  df <- df[!duplicated(df$date, fromLast = TRUE), ]   # keep last price per day
  df[df$date >= START & df$date < LAUNCH, ]
}

new_races <- lapply(old$races, function(r) {
  meta <- races[races$id == r$id, ]
  if (nrow(meta) == 0 || meta$source != "polymarket") return(r)
  hist <- fetch_history(meta$identifier, meta$outcome)
  if (is.null(hist)) { message("WARN: no history for ", r$id); return(r) }

  kept <- Filter(function(h) as.Date(h$date) >= LAUNCH, r$history)
  poll_flat <- r$polls
  back <- lapply(seq_len(nrow(hist)), function(i)
    list(date = format(hist$date[i]), market = hist$market[i], polls = poll_flat, est = TRUE))
  r$history <- c(back, kept)
  message(r$id, ": backfilled ", nrow(hist), " days (", format(min(hist$date)), " to ",
          format(max(hist$date)), "), kept ", length(kept), " live points")
  r
})

old$races <- new_races
write_json(old, data_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
message("Wrote ", data_path)
