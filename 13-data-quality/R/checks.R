# The data quality check suite.
#
# run_checks(data, config) loads the tables into an in-memory DuckDB database, runs the
# SQL checks in sql/ and the statistical checks below, and returns:
#   $summary   one row per check: check, table, status (pass / fail / not enough data),
#              n_flagged, detail
#   $findings  one data frame per check; its `key` column names exactly what was flagged
#              (a row id, a tracker id, a column, a device)
#
# Checks written in SQL: things a query answers directly (duplicates, joins, ranges).
# Checks written in R: things that need statistics (correlation, a drift test) or time
# zones (DuckDB's time-zone support is an optional extension).

library(DBI)
library(duckdb)
library(yaml)

dq_dir <- function() {
  # Folder holding checks.yml and sql/, whether sourced from the repo root or from here.
  for (d in c("13-data-quality", ".", "..", "../..")) {
    if (file.exists(file.path(d, "checks.yml"))) return(normalizePath(d))
  }
  stop("Can't find 13-data-quality/checks.yml")
}

load_config <- function(path = file.path(dq_dir(), "checks.yml")) read_yaml(path)

# Replaces {name} placeholders in a SQL file with values from a named list.
fill_sql <- function(sql, params) {
  for (name in names(params)) sql <- gsub(paste0("{", name, "}"), params[[name]], sql, fixed = TRUE)
  if (grepl("\\{[a-z_]+\\}", sql)) stop("Unfilled placeholder in SQL: ", sql)
  sql
}

sql_params <- function(config) {
  p <- list(expected_trials = config$force_sessions$expected_trials,
            earliest_valid = config$dates$earliest_valid,
            latest_valid = config$dates$latest_valid)
  for (field in names(config$limits)) {
    p[[paste0(field, "_min")]] <- config$limits[[field]][1]
    p[[paste0(field, "_max")]] <- config$limits[[field]][2]
  }
  p
}

run_sql_check <- function(con, name, params) {
  sql <- paste(readLines(file.path(dq_dir(), "sql", paste0(name, ".sql")), warn = FALSE),
               collapse = "\n")
  dbGetQuery(con, fill_sql(sql, params))
}

# ---- Checks written in R ---------------------------------------------------------------

# Columns that are (almost) never filled. The real tracker's team field was 0% populated,
# so any code relying on it was silently wrong.
check_empty_columns <- function(data, config) {
  rows <- list()
  for (table in c("roster", "tracker_links", "pitches", "force_trials", "rom")) {
    # A table with no rows has no empty share to judge (the real archive has no ROM table).
    if (nrow(data[[table]]) == 0) next
    for (col in names(data[[table]])) {
      share <- mean(is.na(data[[table]][[col]]))
      if (share >= config$empty_columns$max_null_share) {
        rows[[length(rows) + 1]] <- data.frame(table = table, key = col, null_share = share)
      }
    }
  }
  if (length(rows) == 0) return(data.frame(table = character(0), key = character(0),
                                           null_share = numeric(0)))
  do.call(rbind, rows)
}

# Force tests are stored with a UTC timestamp. The calendar day must be the facility's
# local day; an evening test (after 6-7 pm Central) is already the next day in UTC.
check_timezone_day_shift <- function(data, config) {
  f <- data$force_trials
  local_day <- as.Date(format(f$test_ts_utc, "%Y-%m-%d", tz = config$local_timezone))
  wrong <- f$test_date != local_day
  data.frame(key = f$trial_id[wrong], stored = f$test_date[wrong], local = local_day[wrong])
}

# Is pitch-type tagging missing at random? If faster (or slower) pitchers are tagged less,
# every metric filtered by pitch type is biased, not just smaller.
check_biased_tag_missingness <- function(data, config) {
  cfg <- config$tag_missingness
  p <- data$pitches
  p <- p[!is.na(p$rel_speed_mph) &
           p$rel_speed_mph >= config$limits$rel_speed_mph[1] &
           p$rel_speed_mph <= config$limits$rel_speed_mph[2], ]
  by_pitcher <- data.frame(
    n = as.vector(table(p$tracker_id)),
    tag_rate = as.vector(tapply(!is.na(p$pitch_type), p$tracker_id, mean)),
    median_velo = as.vector(tapply(p$rel_speed_mph, p$tracker_id, median))
  )
  by_pitcher <- by_pitcher[by_pitcher$n >= cfg$min_pitches_per_pitcher, ]
  if (nrow(by_pitcher) < cfg$min_pitchers) {
    return(list(status = "not enough data", r = NA_real_, n = nrow(by_pitcher)))
  }
  r <- cor(by_pitcher$tag_rate, by_pitcher$median_velo)
  list(status = if (abs(r) > cfg$max_abs_correlation) "fail" else "pass",
       r = r, n = nrow(by_pitcher))
}

# Has a force plate drifted? Compare each device's recent sessions with its own earlier
# sessions. Values are taken relative to the athlete's population average so a device that
# simply saw more college athletes lately doesn't look like drift.
check_device_drift <- function(data, config) {
  cfg <- config$device_drift
  lim <- config$limits$jump_height_in
  f <- data$force_trials
  f <- f[!is.na(f$jump_height_in) & f$jump_height_in >= lim[1] & f$jump_height_in <= lim[2], ]
  f$population <- data$roster$population[match(f$athlete_id, data$roster$athlete_id)]
  sessions <- aggregate(jump_height_in ~ athlete_id + device_id + population + test_ts_utc,
                        data = f, FUN = mean)
  sessions$residual <- sessions$jump_height_in -
    ave(sessions$jump_height_in, sessions$population, FUN = mean)
  local_day <- as.Date(format(sessions$test_ts_utc, "%Y-%m-%d", tz = config$local_timezone))
  cutoff <- as.Date(config$dates$latest_valid) - cfg$recent_days
  sessions$recent <- local_day > cutoff

  rows <- list()
  for (dev in sort(unique(sessions$device_id))) {
    recent <- sessions$residual[sessions$device_id == dev & sessions$recent]
    earlier <- sessions$residual[sessions$device_id == dev & !sessions$recent]
    enough <- length(recent) >= cfg$min_sessions_each_window &&
      length(earlier) >= cfg$min_sessions_each_window
    shift <- if (enough) mean(recent) - mean(earlier) else NA_real_
    t <- if (enough) shift / sqrt(var(recent) / length(recent) + var(earlier) / length(earlier))
         else NA_real_
    rows[[length(rows) + 1]] <- data.frame(
      key = dev, n_recent = length(recent), n_earlier = length(earlier),
      shift_in = shift, t = t,
      status = if (!enough) "not enough data"
               else if (abs(t) >= cfg$min_t && abs(shift) >= cfg$min_shift_in) "fail"
               else "pass"
    )
  }
  do.call(rbind, rows)
}

# ---- Runner ----------------------------------------------------------------------------

run_checks <- function(data, config = load_config()) {
  con <- dbConnect(duckdb(shared_home = FALSE))
  on.exit(dbDisconnect(con, shutdown = TRUE))
  for (table in c("roster", "tracker_links", "pitches", "force_trials", "rom")) {
    dbWriteTable(con, table, data[[table]])
  }
  params <- sql_params(config)

  findings <- list()
  summary <- list()
  add <- function(check, table, status, flagged, detail) {
    findings[[check]] <<- flagged
    summary[[length(summary) + 1]] <<- data.frame(
      check = check, table = table, status = status,
      n_flagged = if (is.data.frame(flagged)) nrow(flagged) else length(flagged),
      detail = detail)
  }
  sql_check <- function(check, table, detail) {
    rows <- run_sql_check(con, check, params)
    add(check, table, if (nrow(rows) > 0) "fail" else "pass", rows, detail)
  }

  empty <- check_empty_columns(data, config)
  add("empty_columns", "all", if (nrow(empty) > 0) "fail" else "pass", empty,
      sprintf("columns at least %.0f%% empty", 100 * config$empty_columns$max_null_share))

  sql_check("impossible_values", "pitches, force_trials, rom", "values outside physical limits")
  sql_check("duplicate_rows", "pitches", "same pitch id loaded more than once")
  sql_check("unlinked_tracker_ids", "pitches", "tracker ids with no athlete link")
  sql_check("orphan_links", "tracker_links", "links to athletes not on the roster")

  tz <- check_timezone_day_shift(data, config)
  add("timezone_day_shift", "force_trials", if (nrow(tz) > 0) "fail" else "pass", tz,
      "stored test day differs from the local day")

  miss <- check_biased_tag_missingness(data, config)
  add("biased_tag_missingness", "pitches", miss$status,
      if (miss$status == "fail") data.frame(key = "pitch_type", r = miss$r)
      else data.frame(key = character(0), r = numeric(0)),
      sprintf("r(tag rate, median velo) = %.2f across %d pitchers", miss$r, miss$n))

  drift <- check_device_drift(data, config)
  drifted <- drift[drift$status == "fail", ]
  add("device_drift", "force_trials",
      if (nrow(drifted) > 0) "fail" else if (all(drift$status == "not enough data"))
        "not enough data" else "pass",
      drifted,
      paste(sprintf("%s shift %+.2f in (t = %.1f)", drift$key, drift$shift_in, drift$t),
            collapse = "; "))

  sql_check("incomplete_sessions", "force_trials",
            sprintf("sessions with fewer than %d trials", config$force_sessions$expected_trials))
  sql_check("out_of_range_dates", "pitches", "session dates outside the valid window")

  list(summary = do.call(rbind, summary), findings = findings)
}
