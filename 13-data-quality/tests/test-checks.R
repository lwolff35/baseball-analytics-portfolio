# Two kinds of checks, two kinds of tests.
#
# Rule checks (a duplicate is a duplicate) must be exact: pass on clean simulated data and
# flag exactly the errors the simulator planted, no more and no fewer, on every seed.
#
# Statistical checks (tag-missingness bias, device drift) decide from noisy data, so on any
# one dataset they can be wrong. They are tested the honest way: across many simulated
# facilities, false alarms on clean data must be rare and planted problems must usually
# be caught. validate_error_rates.R runs the same thing at a larger scale.
#
# From the repository root:  Rscript -e 'testthat::test_dir("13-data-quality/tests")'

library(testthat)
root <- normalizePath(file.path(test_path(), "..", ".."))
source(file.path(root, "synthetic", "simulate_facility.R"))
source(file.path(root, "13-data-quality", "R", "checks.R"))
source(file.path(root, "13-data-quality", "R", "validity_report.R"))

statistical <- c("biased_tag_missingness", "device_drift")

flagged_keys <- function(result, check) sort(unique(as.character(result$findings[[check]]$key)))
planted_keys <- function(sim, check) sort(unique(sim$injected$key[sim$injected$check == check]))

for (seed in c(7, 2026, 31415)) {
  clean <- run_checks(simulate_facility(seed = seed))
  sim <- simulate_facility(seed = seed, inject_errors = TRUE)
  broken <- run_checks(sim)
  rules_clean <- clean$summary[!clean$summary$check %in% statistical, ]
  rules_broken <- broken$summary[!broken$summary$check %in% statistical, ]

  test_that(sprintf("seed %d: every rule check passes on clean data", seed), {
    expect_true(all(rules_clean$status == "pass"),
                info = paste(rules_clean$check[rules_clean$status != "pass"], collapse = ", "))
  })

  test_that(sprintf("seed %d: each rule check flags exactly what was planted", seed), {
    for (check in setdiff(unique(sim$injected$check), statistical)) {
      expect_equal(flagged_keys(broken, check), planted_keys(sim, check), info = check)
    }
    expect_true(all(rules_broken$status == "fail"))
  })

  test_that(sprintf("seed %d: pointblank and SQL agree on impossible values", seed), {
    fails <- validity_failures(validity_agent(sim))
    between <- fails[fails$step == "col_vals_between", ]
    expect_equal(sum(between$n_failed), nrow(broken$findings$impossible_values))
    distinct <- fails[fails$step == "rows_distinct", ]
    # rows_distinct counts both copies of each duplicated pitch.
    expect_equal(distinct$n_failed, 2 * nrow(broken$findings$duplicate_rows))
  })
}

test_that("statistical checks: rare false alarms, planted problems usually caught", {
  config <- load_config()
  n <- 30
  false_alarm <- c(missing = 0, drift = 0)
  caught <- c(missing = 0, drift = 0)
  for (seed in 1000 + seq_len(n)) {
    clean <- simulate_facility(seed = seed)
    broken <- simulate_facility(seed = seed, inject_errors = TRUE)
    false_alarm["missing"] <- false_alarm["missing"] +
      (check_biased_tag_missingness(clean, config)$status == "fail")
    caught["missing"] <- caught["missing"] +
      (check_biased_tag_missingness(broken, config)$status == "fail")
    false_alarm["drift"] <- false_alarm["drift"] +
      any(check_device_drift(clean, config)$status == "fail")
    caught["drift"] <- caught["drift"] +
      ("FD-2" %in% with(check_device_drift(broken, config), key[status == "fail"]))
  }
  expect_lte(max(false_alarm) / n, 0.10)
  expect_gte(min(caught) / n, 0.80)
})

test_that("a table with no rows runs instead of crashing", {
  sim <- simulate_facility(seed = 7)
  sim$rom <- sim$rom[0, ]
  result <- run_checks(sim)
  expect_equal(result$summary$status[result$summary$check == "empty_columns"], "pass")
})

test_that("pitches with no id are not counted as one duplicate", {
  sim <- simulate_facility(seed = 7)
  sim$pitches$pitch_uid[1:5] <- NA
  result <- run_checks(sim)
  expect_equal(result$summary$status[result$summary$check == "duplicate_rows"], "pass")
})

test_that("a placeholder left in SQL is an error, not a silent pass", {
  expect_error(fill_sql("SELECT * FROM t WHERE x > {missing}", list()))
})
