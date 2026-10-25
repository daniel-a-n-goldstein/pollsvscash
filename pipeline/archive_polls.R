# ------------------------------------------------------------------
# Polls vs. Cash — daily archive of the individual polls behind RCP
#
# The RCP feed is a live view: it lists the polls currently in each
# race's average and nothing else, and old polls drop off over time.
# The site only keeps the weekly average, so this script snapshots the
# full per-race poll list once a day:
#
#   pipeline/polls_raw/YYYY-MM-DD.csv        one row per poll per race
#   pipeline/polls_raw/json/YYYY-MM-DD/<race>.json   raw feed, untouched
#
# A poll's release day is the first snapshot it appears in; that is the
# timestamp a "did the money move before the poll?" analysis needs.
# Nothing here feeds the site or the wedge.
#
# Run via .github/workflows/update.yml (daily) and update-polls.yml.
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

races <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
today <- format(Sys.Date(), "%Y-%m-%d")
dir.create(file.path("pipeline/polls_raw/json", today), recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])

rows <- list()
for (i in seq_len(nrow(races))) {
  r <- races[i, ]
  if (is.na(r$rcp_id) || !nzchar(as.character(r$rcp_id))) next
  url <- sprintf("https://orig.realclearpolitics.com/poll/race/%s/polling_data.json", r$rcp_id)
  txt <- tryCatch(readLines(url, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(txt)) { message("WARN: archive fetch failed for ", r$id); next }
  writeLines(txt, file.path("pipeline/polls_raw/json", today, paste0(r$id, ".json")))

  j <- tryCatch(fromJSON(paste(txt, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || length(j$poll) == 0) next

  for (p in j$poll) {
    if (identical(p$type, "rcp_average")) next          # the average is in polls.csv already
    cands <- p$candidate %||% list()
    side  <- Filter(function(c) identical(c$affiliation, r$poll_party), cands)
    other <- Filter(function(c) !identical(c$affiliation, r$poll_party), cands)
    side_v  <- if (length(side) == 1) suppressWarnings(as.numeric(side[[1]]$value)) else NA_real_
    other_v <- if (length(other) >= 1) suppressWarnings(max(vapply(other, function(c) as.numeric(c$value), 0))) else NA_real_
    rows[[length(rows) + 1]] <- data.frame(
      snapshot    = today,
      race        = r$id,
      rcp_id      = r$rcp_id,
      rcp_poll_id = chr(p$id),
      pollster    = chr(p$pollster),
      start_date  = chr(p$data_start_date),
      end_date    = chr(p$data_end_date),
      sample      = chr(p$sampleSize),
      moe         = chr(p$marginError),
      side_name   = if (length(side) == 1) chr(side[[1]]$name) else NA_character_,
      side_value  = side_v,
      other_name  = if (length(other) >= 1) paste(vapply(other, function(c) chr(c$name), ""), collapse = "/") else NA_character_,
      other_value = other_v,
      margin      = round(side_v - other_v, 1),
      spread      = chr(p$spread_value),
      link        = chr(p$link),
      stringsAsFactors = FALSE)
  }
}

out <- do.call(rbind, rows)
if (is.null(out) || nrow(out) == 0) { message("WARN: nothing archived"); quit(status = 0) }
write.csv(out, file.path("pipeline/polls_raw", paste0(today, ".csv")), row.names = FALSE)
message("Archived ", nrow(out), " polls across ", length(unique(out$race)), " races -> pipeline/polls_raw/", today, ".csv")
