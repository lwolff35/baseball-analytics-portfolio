# Runs the whole check suite twice: on clean simulated data, then on the same data with
# known errors planted. Every check should pass the first time and fail the second.
#
# From the repository root:  Rscript 13-data-quality/run_demo.R

source("synthetic/simulate_facility.R")
source("13-data-quality/R/checks.R")

clean <- simulate_facility(seed = 2026, inject_errors = FALSE)
broken <- simulate_facility(seed = 2026, inject_errors = TRUE)

cat(sprintf("Simulated: %d athletes, %d pitches, %d force trials, %d ROM measurements\n\n",
            nrow(clean$roster), nrow(clean$pitches), nrow(clean$force_trials),
            nrow(clean$rom)))

show <- function(label, result) {
  cat(label, "\n")
  s <- result$summary
  print(s[, c("check", "status", "n_flagged", "detail")], row.names = FALSE, right = FALSE)
  cat("\n")
}
show("== Clean data ==", run_checks(clean))
show("== Data with planted errors ==", run_checks(broken))
