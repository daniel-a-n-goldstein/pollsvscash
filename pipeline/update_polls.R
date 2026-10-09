# ------------------------------------------------------------------
# Polls vs. Cash — weekly poll-benchmark refresh
#
# For every race in pipeline/races.csv that has an rcp_id, fetch the
# RealClearPolling average from RCP's public JSON feed and write the
# margin (for the side the market is about) to pipeline/polls.csv.
# Races without an rcp_id (e.g. chamber control, which needs a model
# probability rather than a margin) are carried over from
# pipeline/polls_manual.csv unchanged.
#
# Run locally with:  Rscript pipeline/update_polls.R
# Runs automatically via .github/workflows/update-polls.yml (Sundays)
# Only dependency: jsonlite
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))

races  <- read.csv("pipeline/races.csv", stringsAsFactors = FALSE)
manual <- if (file.exists("pipeline/polls_manual.csv"))
  read.csv("pipeline/polls_manual.csv", stringsAsFactors = FALSE) else NULL

today <- format(Sys.Date(), "%Y-%m-%d")

# RCP's per-race JSON feed. poll[[1]] (type "rcp_average") is the
# current RCP Average; the remaining entries are the individual polls.
fetch_rcp_average <- function(race_id) {
  url <- sprintf("https://orig.realclearpolitics.com/poll/race/%s/polling_data.json", race_id)
  j <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || length(j$poll) == 0) return(NULL)
  avg <- Filter(function(p) identical(p$type, "rcp_average"), j$poll)
  if (length(avg) == 0) return(NULL)
  avg <- avg[[1]]
  cands <- do.call(rbind, lapply(avg$candidate, function(c)
    data.frame(name = c$name, party = c$affiliation, value = as.numeric(c$value),
               stringsAsFactors = FALSE)))
  list(title = j$moduleInfo$title, date = avg$date, cands = cands)
}

rows <- lapply(seq_len(nrow(races)), function(i) {
  r <- races[i, ]
  has_rcp <- !is.na(r$rcp_id) && nzchar(as.character(r$rcp_id))

  if (!has_rcp) {
    m <- if (!is.null(manual)) manual[manual$id == r$id, ] else manual
    if (is.null(m) || nrow(m) == 0) {
      message("WARN: ", r$id, " has no rcp_id and no row in polls_manual.csv")
      return(data.frame(id = r$id, poll_prob = NA, poll_margin = NA, poll_date = NA,
                        note = "no benchmark", stringsAsFactors = FALSE))
    }
    return(data.frame(id = r$id, poll_prob = m$poll_prob[1], poll_margin = NA,
                      poll_date = m$poll_date[1], note = m$note[1], stringsAsFactors = FALSE))
  }

  a <- fetch_rcp_average(r$rcp_id)
  if (is.null(a)) {
    message("WARN: RCP fetch failed for ", r$id, " (race ", r$rcp_id, ")")
    return(NULL)   # keep whatever polls.csv already has for this race
  }

  side  <- a$cands[a$cands$party == r$poll_party, ]
  other <- a$cands[a$cands$party != r$poll_party, ]
  if (nrow(side) != 1 || nrow(other) < 1) {
    message("WARN: could not identify ", r$poll_party, " candidate for ", r$id)
    return(NULL)
  }
  margin <- round(side$value - max(other$value), 1)
  data.frame(
    id = r$id, poll_prob = NA, poll_margin = margin, poll_date = a$date,
    note = sprintf("RCP average %s: %s %+.1f (%s vs %s), fetched %s",
                   a$date, side$name, margin, side$name,
                   paste(other$name, collapse = "/"), today),
    stringsAsFactors = FALSE)
})

new <- do.call(rbind, Filter(Negate(is.null), rows))

# merge with existing polls.csv so a failed fetch keeps the old value
if (file.exists("pipeline/polls.csv")) {
  old <- read.csv("pipeline/polls.csv", stringsAsFactors = FALSE)
  if (!"poll_date" %in% names(old)) old$poll_date <- NA
  keep <- old[!old$id %in% new$id, c("id", "poll_prob", "poll_margin", "poll_date", "note")]
  new <- rbind(new, keep)
}
new <- new[match(races$id, new$id), ]
new <- new[!is.na(new$id), ]

write.csv(new, "pipeline/polls.csv", row.names = FALSE, na = "")
message("Wrote pipeline/polls.csv — ", nrow(new), " races, ", today)
print(new[, c("id", "poll_prob", "poll_margin", "poll_date")])
