# ------------------------------------------------------------------
# Polls vs. Cash — does the money move before the poll?
#
# Event study around poll releases. A poll's release day is the first
# daily snapshot in pipeline/polls_raw/ it appears in (so only polls
# first seen AFTER the first snapshot have a known release day; older
# polls are excluded). For each release we ask which way the poll
# "surprised" relative to the benchmark the site was using that day
# (the poll's margin minus the RCP-average margin in force, recovered
# from the poll-implied probability via the same probit), and then
# measure the market's move, signed so that + means "toward where the
# poll pointed":
#
#   pre  = market[t-1] - market[t-4]   (the three days before release)
#   day  = market[t+1] - market[t-1]   (release day itself)
#   post = market[t+3] - market[t+1]   (the two days after)
#
# If the money anticipates polls, pre > 0 on average. If it merely
# reacts to them, day > 0 and pre ≈ 0. Everything is pooled across
# races; expect a few dozen releases, so this is descriptive.
#
# Inputs:  pipeline/polls_raw/*.csv, docs/data.json
# Outputs: analysis/output/event_releases.csv  (one row per release)
#          analysis/output/event_summary.csv
#          analysis/output/event_study.png
# Only dependency: jsonlite. Run: Rscript analysis/event_study.R
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))
dir.create("analysis/output", showWarnings = FALSE, recursive = TRUE)
SIGMA <- 5.5
ELECTION <- as.Date("2026-11-03")

# ---- release days from the snapshots --------------------------------
files <- sort(list.files("pipeline/polls_raw", pattern = "^\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE))
stopifnot(length(files) >= 2)
snaps <- lapply(files, function(f) { x <- read.csv(f, stringsAsFactors = FALSE); x$snapshot <- as.Date(x$snapshot); x })
all <- do.call(rbind, snaps)
all$key <- paste(all$race, ifelse(is.na(all$rcp_poll_id) | all$rcp_poll_id == "", paste(all$pollster, all$end_date), all$rcp_poll_id))
first_seen <- aggregate(snapshot ~ key, all, min)
names(first_seen)[2] <- "release"
polls <- merge(all[!duplicated(all$key), c("key", "race", "pollster", "start_date", "end_date", "margin")], first_seen, by = "key")
polls <- polls[polls$release > min(all$snapshot), ]          # release day known only after the first snapshot
polls <- polls[!is.na(polls$margin) & polls$release < ELECTION, ]
message(nrow(polls), " polls with a known release day")

# ---- market & benchmark series --------------------------------------
d <- fromJSON("docs/data.json", simplifyVector = FALSE)
H <- do.call(rbind, lapply(d$races, function(r) data.frame(
  race = r$id,
  date = as.Date(vapply(r$history, function(p) p$date, "")),
  market = vapply(r$history, function(p) if (is.null(p$market)) NA_real_ else as.numeric(p$market), 0),
  polls  = vapply(r$history, function(p) if (is.null(p$polls))  NA_real_ else as.numeric(p$polls),  0),
  stringsAsFactors = FALSE)))
# value on a date, falling back to the most recent earlier date (a missed run is not a zero)
at <- function(race, date, col) {
  x <- H[H$race == race & H$date <= date, ]
  if (nrow(x) == 0) return(NA_real_)
  x[[col]][which.max(x$date)]
}

ev <- do.call(rbind, lapply(seq_len(nrow(polls)), function(i) {
  p <- polls[i, ]; t <- p$release
  bench_prob <- at(p$race, t - 1, "polls")                   # benchmark in force the day before release
  if (is.na(bench_prob)) return(NULL)
  bench_margin <- SIGMA * qnorm(min(max(bench_prob, 0.5), 99.5) / 100)
  surprise <- p$margin - bench_margin                        # > 0: poll more Democratic than the benchmark
  s <- sign(surprise); if (s == 0) return(NULL)
  m <- function(k) at(p$race, t + k, "market")
  data.frame(race = p$race, pollster = p$pollster, release = t, field_end = p$end_date,
             poll_margin = p$margin, bench_margin = round(bench_margin, 1), surprise = round(surprise, 1),
             pre  = s * (m(-1) - m(-4)),
             day  = s * (m(1)  - m(-1)),
             post = s * (m(3)  - m(1)),
             path = I(list(vapply(-4:3, function(k) s * (m(k) - m(-1)), 0))),
             stringsAsFactors = FALSE)
}))
if (is.null(ev) || nrow(ev) == 0) stop("no usable releases yet")

out <- ev[, setdiff(names(ev), "path")]
write.csv(out, "analysis/output/event_releases.csv", row.names = FALSE)

se <- function(x) { x <- x[!is.na(x)]; if (length(x) < 2) NA else sd(x) / sqrt(length(x)) }
summ <- data.frame(window = c("pre (t-4 to t-1)", "release day (t-1 to t+1)", "post (t+1 to t+3)"),
                   mean_signed_move = c(mean(ev$pre, na.rm = TRUE), mean(ev$day, na.rm = TRUE), mean(ev$post, na.rm = TRUE)),
                   se = c(se(ev$pre), se(ev$day), se(ev$post)),
                   share_positive = c(mean(ev$pre > 0, na.rm = TRUE), mean(ev$day > 0, na.rm = TRUE), mean(ev$post > 0, na.rm = TRUE)),
                   n = c(sum(!is.na(ev$pre)), sum(!is.na(ev$day)), sum(!is.na(ev$post))))
# big surprises only (|surprise| >= 3 points) — where a reaction should be visible if there is one
big <- ev[abs(ev$surprise) >= 3, ]
summ_big <- if (nrow(big) >= 5) data.frame(window = paste(summ$window, "| big surprises"),
  mean_signed_move = c(mean(big$pre, na.rm = TRUE), mean(big$day, na.rm = TRUE), mean(big$post, na.rm = TRUE)),
  se = c(se(big$pre), se(big$day), se(big$post)),
  share_positive = c(mean(big$pre > 0, na.rm = TRUE), mean(big$day > 0, na.rm = TRUE), mean(big$post > 0, na.rm = TRUE)),
  n = rep(nrow(big), 3)) else NULL
summ <- rbind(summ, summ_big)
cat("\n=== Market move in the direction of the poll's surprise, pooled (points) ===\n"); print(summ, row.names = FALSE, digits = 3)
write.csv(summ, "analysis/output/event_summary.csv", row.names = FALSE)

# ---- figure: average signed market path around release ---------------
paths <- do.call(rbind, ev$path); ks <- -4:3
avg <- colMeans(paths, na.rm = TRUE); s_e <- apply(paths, 2, se)
png("analysis/output/event_study.png", width = 1200, height = 800, res = 150)
par(mar = c(4.5, 4.5, 3, 1), bg = "white")
plot(ks, avg, type = "n", ylim = range(c(avg - 2 * s_e, avg + 2 * s_e, 0), na.rm = TRUE),
     xlab = "days relative to poll release (t = first day the poll is listed)",
     ylab = "market move toward the poll's direction (pts, relative to t-1)",
     main = sprintf("Market around %d poll releases, pooled across races", nrow(ev)), xaxt = "n")
axis(1, at = ks); abline(h = 0, col = "grey60"); abline(v = -0.5, col = "grey75", lty = 2)
polygon(c(ks, rev(ks)), c(avg - 2 * s_e, rev(avg + 2 * s_e)), col = "#FFB52E33", border = NA)
lines(ks, avg, col = "#D9950F", lwd = 2.5); points(ks, avg, pch = 16, col = "#D9950F")
text(-0.5, par("usr")[3] + 0.06 * diff(par("usr")[3:4]), "release", pos = 4, cex = .75, col = "grey40")
dev.off()
message("Wrote analysis/output/event_{releases,summary}.csv and event_study.png")
