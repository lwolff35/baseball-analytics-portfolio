# A second, independent implementation of the physical-limits check using the
# pointblank package. It produces a browsable validation report, the kind of thing a
# data technician hands a coach or a vendor. The limits come from the same checks.yml.

library(pointblank)

validity_agent <- function(data, config = load_config()) {
  lim <- config$limits
  agents <- list(
    pitches = create_agent(tbl = data$pitches, tbl_name = "pitches",
                           label = "Pitch tracker: physical limits") |>
      col_vals_between(rel_speed_mph, lim$rel_speed_mph[1], lim$rel_speed_mph[2],
                       na_pass = TRUE) |>
      col_vals_between(spin_rpm, lim$spin_rpm[1], lim$spin_rpm[2], na_pass = TRUE) |>
      col_vals_not_null(c(pitch_uid, tracker_id, session_date)) |>
      rows_distinct(columns = vars(pitch_uid)),
    force_trials = create_agent(tbl = data$force_trials, tbl_name = "force_trials",
                                label = "Force plate: physical limits") |>
      col_vals_between(jump_height_in, lim$jump_height_in[1], lim$jump_height_in[2],
                       na_pass = TRUE),
    rom = create_agent(tbl = data$rom, tbl_name = "rom",
                       label = "Range of motion: physical limits") |>
      col_vals_between(degrees, lim$rom_degrees[1], lim$rom_degrees[2], na_pass = TRUE)
  )
  lapply(agents, interrogate)
}

# Number of failing rows per validation step, for comparing against the SQL check.
validity_failures <- function(agents) {
  do.call(rbind, lapply(names(agents), function(name) {
    x <- agents[[name]]$validation_set
    data.frame(table = name, step = x$assertion_type,
               column = vapply(x$column, function(c) paste(unlist(c), collapse = ","), ""),
               n_failed = x$n_failed)
  }))
}
