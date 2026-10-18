# Simulates a training facility's data: a roster, pitch-tracker sessions, force-plate
# trials and range-of-motion measurements. Table shapes mirror a real facility's
# platform; every value is random. No real athlete is represented.
#
# simulate_facility(seed, inject_errors = FALSE) returns a list:
#   $roster, $tracker_links, $pitches, $force_trials, $rom   (data frames)
#   $injected  data frame of every error planted on purpose: check, table, key
#              (empty when inject_errors = FALSE). Tests compare the checks' findings
#              against this answer key.

simulate_facility <- function(seed = 1, n_athletes = 150, inject_errors = FALSE,
                              start_date = as.Date("2025-10-01"),
                              end_date = as.Date("2026-09-30"),
                              local_tz = "America/Chicago") {
  set.seed(seed)
  days <- as.integer(end_date - start_date)

  # ---- Roster -------------------------------------------------------------------
  levels <- c("Youth", "High School", "College", "Pro")
  population <- sample(levels, n_athletes, replace = TRUE, prob = c(.10, .55, .30, .05))
  age_years <- c(Youth = 12, "High School" = 16, College = 20, Pro = 24)[population] +
    runif(n_athletes, -1.5, 1.5)
  roster <- data.frame(
    athlete_id = sprintf("A%04d", seq_len(n_athletes)),
    population = population,
    birth_date = end_date - round(age_years * 365.25),
    throws = sample(c("Right", "Left"), n_athletes, replace = TRUE, prob = c(.75, .25))
  )

  # ---- Tracker identity links (about 80% of athletes throw on the tracker) ----------
  throwers <- roster$athlete_id[runif(n_athletes) < 0.80]
  tracker_links <- data.frame(
    athlete_id = throwers,
    tracker_id = sprintf("T%06d", sample(1e5:9e5, length(throwers)))
  )

  # ---- Pitches ----------------------------------------------------------------------
  # Each thrower has a true fastball velo by level; sessions of ~25 pitches.
  base_velo <- c(Youth = 60, "High School" = 76, College = 84, Pro = 90)
  pitch_mix <- data.frame(
    pitch_type = c("Fastball", "Slider", "Changeup", "Curveball"),
    prob = c(.55, .20, .15, .10),
    velo_offset = c(0, -8, -7, -12),
    ivb = c(15, 2, 8, -10),
    hb = c(8, -4, 12, -6)
  )
  pitch_rows <- list()
  for (i in seq_along(throwers)) {
    a <- throwers[i]
    pop <- roster$population[roster$athlete_id == a]
    true_velo <- rnorm(1, base_velo[[pop]], 3)
    n_sessions <- sample(1:8, 1)
    session_days <- sort(start_date + sample(0:days, n_sessions))
    for (d in seq_along(session_days)) {
      n <- max(5, round(rnorm(1, 25, 6)))
      k <- sample(nrow(pitch_mix), n, replace = TRUE, prob = pitch_mix$prob)
      pitch_rows[[length(pitch_rows) + 1]] <- data.frame(
        tracker_id = tracker_links$tracker_id[i],
        session_date = session_days[d],
        session_type = "Live",
        true_type = pitch_mix$pitch_type[k],
        rel_speed_mph = round(true_velo + pitch_mix$velo_offset[k] + rnorm(n, 0, 1.5), 1),
        ivb_in = round(pitch_mix$ivb[k] + rnorm(n, 0, 2), 1),
        hb_in = round(pitch_mix$hb[k] + rnorm(n, 0, 2), 1),
        spin_rpm = round(rnorm(n, 2200, 200)),
        pitcher_team = sample(c("BSF_HS", "BSF_COL"), 1)
      )
    }
  }
  pitches <- do.call(rbind, pitch_rows)
  pitches$pitch_uid <- sprintf("P%07d", seq_len(nrow(pitches)))
  # Clean data: half the pitches are untagged, completely at random.
  tagged <- runif(nrow(pitches)) < 0.5
  pitches$pitch_type <- ifelse(tagged, pitches$true_type, NA)

  # ---- Force-plate trials (CMJ, 3 trials per session) --------------------------------
  base_jump <- c(Youth = 12, "High School" = 15, College = 18, Pro = 20)
  force_rows <- list()
  for (a in roster$athlete_id) {
    pop <- roster$population[roster$athlete_id == a]
    true_jump <- rnorm(1, base_jump[[pop]], 2.5)
    n_sessions <- sample(1:3, 1, prob = c(.5, .35, .15))
    for (s in seq_len(n_sessions)) {
      day <- start_date + sample(0:days, 1)
      # Tests run between 2 pm and 9 pm local time.
      local_time <- as.POSIXct(paste(day, "14:00:00"), tz = local_tz) +
        sample(0:(7 * 3600), 1)
      session_jump <- true_jump + rnorm(1, 0, 0.6)
      force_rows[[length(force_rows) + 1]] <- data.frame(
        athlete_id = a,
        device_id = sample(c("FD-1", "FD-2"), 1),
        test_type = "CMJ",
        test_ts_utc = rep(as.POSIXct(format(local_time, tz = "UTC"), tz = "UTC"), 3),
        test_date = as.Date(format(local_time, "%Y-%m-%d", tz = local_tz)),
        trial_no = 1:3,
        jump_height_in = round(session_jump + rnorm(3, 0, 0.4), 2)
      )
    }
  }
  force_trials <- do.call(rbind, force_rows)
  force_trials$trial_id <- sprintf("F%06d", seq_len(nrow(force_trials)))

  # ---- Range of motion (shoulder ER/IR, both sides, on each force-test day) ----------
  rom_days <- unique(force_trials[, c("athlete_id", "test_date")])
  rom <- merge(rom_days, expand.grid(measure = c("shoulder_er", "shoulder_ir"),
                                     side = c("Left", "Right"),
                                     stringsAsFactors = FALSE))
  names(rom)[names(rom) == "test_date"] <- "measure_date"
  rom$degrees <- round(ifelse(rom$measure == "shoulder_er",
                              rnorm(nrow(rom), 110, 10), rnorm(nrow(rom), 50, 8)))
  rom$rom_id <- sprintf("R%06d", seq_len(nrow(rom)))

  injected <- data.frame(check = character(0), table = character(0), key = character(0))
  out <- list(roster = roster, tracker_links = tracker_links, pitches = pitches,
              force_trials = force_trials, rom = rom)

  if (inject_errors) {
    res <- inject_known_errors(out, end_date, local_tz)
    out <- res$data
    injected <- res$injected
  }
  out$pitches$true_type <- NULL   # the simulator's private truth; real data never has it
  out$injected <- injected
  out
}

# Plants one family of error per check, and records exactly what was planted.
inject_known_errors <- function(d, end_date, local_tz) {
  log <- list()
  note <- function(check, table, key) {
    log[[length(log) + 1]] <<- data.frame(check = check, table = table, key = key)
  }

  # 1. A column that is never filled (the real tracker's team field was 0% populated).
  d$pitches$pitcher_team <- NA_character_
  note("empty_columns", "pitches", "pitcher_team")

  # 2. Impossible values.
  bad <- sample(nrow(d$pitches), 8)
  d$pitches$rel_speed_mph[bad] <- sample(c(0, 4.2, 128, 141), 8, replace = TRUE)
  note("impossible_values", "pitches", d$pitches$pitch_uid[bad])
  # (first trials only, so step 9's trial removal can't delete a planted error)
  bad <- sample(which(d$force_trials$trial_no == 1), 3)
  d$force_trials$jump_height_in[bad] <- -abs(d$force_trials$jump_height_in[bad])
  note("impossible_values", "force_trials", d$force_trials$trial_id[bad])
  bad <- sample(nrow(d$rom), 3)
  d$rom$degrees[bad] <- 300
  note("impossible_values", "rom", d$rom$rom_id[bad])

  # 3. The same pitch loaded twice (two exports overlapping).
  dup <- sample(nrow(d$pitches), 15)
  d$pitches <- rbind(d$pitches, d$pitches[dup, ])
  note("duplicate_rows", "pitches", d$pitches$pitch_uid[dup])

  # 4. Pitches from tracker ids with no athlete link (a new pitcher never matched).
  linked <- unique(d$pitches$tracker_id)
  stray <- sample(linked, 2)
  for (k in seq_along(stray)) {
    d$pitches$tracker_id[d$pitches$tracker_id == stray[k]] <- sprintf("T99999%d", k)
    d$tracker_links <- d$tracker_links[d$tracker_links$tracker_id != stray[k], ]
  }
  note("unlinked_tracker_ids", "pitches", sprintf("T99999%d", seq_along(stray)))

  # 5. Links that point at athletes missing from the roster (a deleted athlete).
  orphans <- data.frame(athlete_id = c("A9998", "A9999"), tracker_id = c("T888881", "T888882"))
  d$tracker_links <- rbind(d$tracker_links, orphans)
  note("orphan_links", "tracker_links", orphans$athlete_id)

  # 6. Evening tests dated by the UTC day instead of the local day.
  utc_day <- as.Date(format(d$force_trials$test_ts_utc, "%Y-%m-%d", tz = "UTC"))
  shifted <- utc_day != d$force_trials$test_date
  d$force_trials$test_date[shifted] <- utc_day[shifted]
  note("timezone_day_shift", "force_trials", d$force_trials$trial_id[shifted])

  # 7. Tags missing non-randomly: faster throwers get tagged less often.
  v <- ave(d$pitches$rel_speed_mph, d$pitches$tracker_id, FUN = function(x) median(x))
  z <- (v - mean(v)) / sd(v)
  # A planted hazard, deliberately strong. (An earlier analysis suspected r = -0.29 in the
  # real data; the full-archive run found r = -0.05.)
  p_tag <- plogis(-0.5 * z)
  d$pitches$pitch_type <- ifelse(runif(nrow(d$pitches)) < p_tag, d$pitches$true_type, NA)
  note("biased_tag_missingness", "pitches", "pitch_type")

  # 8. One force plate drifts upward by 15% for its last 4 months (calibration slipping).
  drift_from <- end_date - 120
  drift <- d$force_trials$device_id == "FD-2" & d$force_trials$test_date >= drift_from
  d$force_trials$jump_height_in[drift] <- round(d$force_trials$jump_height_in[drift] * 1.15, 2)
  note("device_drift", "force_trials", "FD-2")

  # 9. Sessions saved with a single trial instead of three.
  session_key <- paste(d$force_trials$athlete_id, d$force_trials$test_ts_utc)
  cut <- sample(unique(session_key[d$force_trials$trial_no == 1]), 4)
  drop <- session_key %in% cut & d$force_trials$trial_no > 1
  d$force_trials <- d$force_trials[!drop, ]
  note("incomplete_sessions", "force_trials",
       d$force_trials$trial_id[paste(d$force_trials$athlete_id, d$force_trials$test_ts_utc) %in% cut])

  # 10. Dates outside the possible window (a clock set wrong, a typo'd year).
  bad <- sample(nrow(d$pitches), 3)
  d$pitches$session_date[bad] <- c(end_date + 400, as.Date("2015-06-01"), end_date + 30)
  note("out_of_range_dates", "pitches", d$pitches$pitch_uid[bad])

  # A later step can delete a row an earlier step planted an error on (step 9 removes
  # trials). Keep only answer-key entries that still exist.
  injected <- do.call(rbind, log)
  id_cols <- c(pitches = "pitch_uid", force_trials = "trial_id", rom = "rom_id")
  is_row_key <- injected$table %in% names(id_cols) &
    grepl("^[PFR][0-9]{6,7}$", injected$key)
  still_there <- mapply(function(table, key) key %in% d[[table]][[id_cols[[table]]]],
                        injected$table[is_row_key], injected$key[is_row_key])
  injected <- injected[!is_row_key | replace(is_row_key, is_row_key, still_there), ]
  list(data = d, injected = injected)
}
