# How often are the statistical checks wrong? Simulates many facilities, with and without
# a planted problem, and counts false alarms and misses. Also sweeps the size of a device
# drift to show the smallest drift the check reliably catches.
#
# From the repository root:  Rscript 13-data-quality/validate_error_rates.R [n_seeds]

source("synthetic/simulate_facility.R")
source("13-data-quality/R/checks.R")

args <- commandArgs(trailingOnly = TRUE)
n_seeds <- if (length(args) >= 1) as.integer(args[1]) else 200
config <- load_config()
seeds <- 5000 + seq_len(n_seeds)

drift_sizes <- c(0, 0.05, 0.10, 0.15, 0.20)
rows <- list()
for (seed in seeds) {
  clean <- simulate_facility(seed = seed)
  broken <- simulate_facility(seed = seed, inject_errors = TRUE)
  rows[[length(rows) + 1]] <- data.frame(
    seed = seed,
    missing_false_alarm = check_biased_tag_missingness(clean, config)$status == "fail",
    missing_caught = check_biased_tag_missingness(broken, config)$status == "fail"
  )
  # Drift sweep: apply drifts of several sizes to the clean data's FD-2, last 120 days.
  recent <- clean$force_trials$device_id == "FD-2" &
    clean$force_trials$test_date >= as.Date(config$dates$latest_valid) -
      config$device_drift$recent_days
  for (size in drift_sizes) {
    d <- clean
    d$force_trials$jump_height_in[recent] <- d$force_trials$jump_height_in[recent] * (1 + size)
    res <- check_device_drift(d, config)
    rows[[length(rows)]][[sprintf("drift_%02.0f", 100 * size)]] <-
      "FD-2" %in% res$key[res$status == "fail"]
  }
}
r <- do.call(rbind, rows)

cat(sprintf("Simulated facilities: %d\n\n", n_seeds))
cat("Tag-missingness bias check\n")
cat(sprintf("  false alarm rate on clean data: %.1f%%\n", 100 * mean(r$missing_false_alarm)))
cat(sprintf("  detection rate, planted bias:   %.1f%%\n\n", 100 * mean(r$missing_caught)))
cat("Device drift check (share of facilities where a drifted FD-2 is flagged)\n")
for (size in drift_sizes) {
  col <- sprintf("drift_%02.0f", 100 * size)
  label <- if (size == 0) "no drift (false alarm rate)" else sprintf("+%.0f%% drift", 100 * size)
  cat(sprintf("  %-28s %5.1f%%\n", label, 100 * mean(r[[col]])))
}

# Saved for the write-up (report.qmd). YAML, not CSV: these are summary results, not data.
dir.create("13-data-quality/results", showWarnings = FALSE)
yaml::write_yaml(list(
  n_facilities = n_seeds,
  tag_missingness = list(false_alarm_rate = mean(r$missing_false_alarm),
                         detection_rate = mean(r$missing_caught)),
  device_drift = data.frame(
    drift = drift_sizes,
    flagged_rate = vapply(drift_sizes, function(s) mean(r[[sprintf("drift_%02.0f", 100 * s)]]), 0)
  )
), "13-data-quality/results/error_rates.yml")
cat("\nSaved 13-data-quality/results/error_rates.yml\n")
