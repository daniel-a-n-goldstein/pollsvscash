# ------------------------------------------------------------------
# Polls vs. Cash — who closed the gap?
#
# Decomposes the change in each race's wedge (market − polls) between
# launch (first non-estimated point, 2026-10-09) and election eve
# (2026-11-02) into the part due to the market moving and the part due
# to the poll benchmark moving. Also splits day-to-day wedge changes
# into "days the poll side updated" (Sundays, or whenever polls.csv
# changed) and all other days, which is the cleanest statement of how
# much of the convergence came from each side.
#
# Inputs:  docs/data.json
# Outputs: analysis/output/decomposition_by_race.csv
#          analysis/output/decomposition_daily.csv
#          analysis/output/decomposition.png
# Only dependency: jsonlite. Run: Rscript analysis/decomposition.R
# ------------------------------------------------------------------

suppressMessages(library(jsonlite))
dir.create("analysis/output", showWarnings = FALSE, recursive = TRUE)

EVE <- as.Date("2026-11-02")
d <- fromJSON("docs/data.json", simplifyVector = FALSE)

hist_df <- function(r) {
  h <- r$history
  data.frame(
    race   = r$id,
    date   = as.Date(vapply(h, function(p) p$date, "")),
    market = vapply(h, function(p) if (is.null(p$market)) NA_real_ else as.numeric(p$market), 0),
    polls  = vapply(h, function(p) if (is.null(p$polls))  NA_real_ else as.numeric(p$polls),  0),
    est    = vapply(h, function(p) isTRUE(p$est), TRUE),
    stringsAsFactors = FALSE)
}
H <- do.call(rbind, lapply(d$races, hist_df))
H <- H[!is.na(H$market) & !is.na(H$polls), ]
H <- H[order(H$race, H$date), ]
H$wedge <- H$market - H$polls

# ---- launch → eve, per race ----------------------------------------
by_race <- do.call(rbind, lapply(split(H, H$race), function(x) {
  live <- x[!x$est & x$date <= EVE, ]
  if (nrow(live) < 2) return(NULL)
  a <- live[1, ]; b <- live[nrow(live), ]
  data.frame(race = a$race, from = a$date, to = b$date,
             market_start = a$market, market_end = b$market, d_market = b$market - a$market,
             polls_start  = a$polls,  polls_end  = b$polls,  d_polls  = b$polls  - a$polls,
             wedge_start  = a$wedge,  wedge_end  = b$wedge,
             gap_closed   = abs(a$wedge) - abs(b$wedge),          # > 0: converged
             # share of the *convergence* attributable to each side: a side "closes" the gap
             # when it moves toward the other side's number; sign relative to the starting wedge
             closed_by_market = -sign(a$wedge) * (b$market - a$market),
             closed_by_polls  =  sign(a$wedge) * (b$polls  - a$polls),
             stringsAsFactors = FALSE)
}))
by_race <- by_race[order(-abs(by_race$wedge_start)), ]
write.csv(by_race, "analysis/output/decomposition_by_race.csv", row.names = FALSE)

# ---- day-to-day: poll-update days vs. market-only days ---------------
daily <- do.call(rbind, lapply(split(H, H$race), function(x) {
  x <- x[!x$est & x$date <= EVE, ]
  if (nrow(x) < 2) return(NULL)
  data.frame(race = x$race[-1], date = x$date[-1],
             d_market = diff(x$market), d_polls = diff(x$polls), d_wedge = diff(x$wedge),
             d_abs_wedge = diff(abs(x$wedge)),
             poll_day = diff(x$polls) != 0, stringsAsFactors = FALSE)
}))
write.csv(daily, "analysis/output/decomposition_daily.csv", row.names = FALSE)

summ <- data.frame(
  side = c("market (all days)", "polls (update days only)"),
  total_abs_movement = c(sum(abs(daily$d_market)), sum(abs(daily$d_polls))),
  net_change_in_abs_wedge = c(sum(daily$d_abs_wedge[!daily$poll_day]), sum(daily$d_abs_wedge[daily$poll_day])),
  n_days = c(sum(!daily$poll_day), sum(daily$poll_day)))
cat("\n=== Launch to eve, all races pooled ===\n")
cat(sprintf("Total |movement| (NB: market is daily, polls are a weekly step series, so this is biased toward the market): market %.1f pts, polls %.1f pts\n", sum(abs(by_race$d_market)), sum(abs(by_race$d_polls))))
cat(sprintf("Sum of |wedge| at launch %.1f -> at eve %.1f (closed %.1f)\n", sum(abs(by_race$wedge_start)), sum(abs(by_race$wedge_end)), sum(by_race$gap_closed)))
cat(sprintf("Of which closed by the market: %.1f; by the polls: %.1f\n", sum(by_race$closed_by_market), sum(by_race$closed_by_polls)))
cat("\n=== Day-to-day: change in sum |wedge| on poll-update days vs market-only days ===\n"); print(summ, row.names = FALSE)
write.csv(summ, "analysis/output/decomposition_summary.csv", row.names = FALSE)

# ---- figure ---------------------------------------------------------
png("analysis/output/decomposition.png", width = 1400, height = 900, res = 150)
par(mar = c(4, 11, 3, 6), bg = "white")
n <- nrow(by_race); yy <- rev(seq_len(n))
lim <- max(abs(c(by_race$d_market, by_race$d_polls)), 2) * 1.15
plot(NA, xlim = c(-lim, lim), ylim = c(0.5, n + 0.5), yaxt = "n", ylab = "", xlab = "change, percentage points (Democratic side)",
     main = "Launch to election eve: how far each side moved")
abline(v = 0, col = "grey60"); abline(h = yy, col = "grey92")
rect(0, yy + 0.05, by_race$d_market, yy + 0.38, col = "#FFB52E", border = NA)
rect(0, yy - 0.38, by_race$d_polls,  yy - 0.05, col = "#52D8C4", border = NA)
axis(2, at = yy, labels = by_race$race, las = 1, cex.axis = .8)
text(lim, yy, sprintf("%+.1f -> %+.1f", by_race$wedge_start, by_race$wedge_end), pos = 2, cex = .7, col = "grey30", xpd = TRUE)
legend("bottomright", fill = c("#FFB52E", "#52D8C4"), border = NA, bty = "n", cex = .8,
       legend = c("market price", "poll-implied probability"))
dev.off()
message("Wrote analysis/output/decomposition_{by_race,daily,summary}.csv and decomposition.png")
