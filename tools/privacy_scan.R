# Privacy scan: blocks a commit that could leak real athlete or facility data.
#
# Runs on every file git would commit (tracked + untracked, minus .gitignore).
# Fails (exit status 1) on:
#   - any name on the private denylist (athlete names, staff names)
#   - a TrackMan player id, a VALD profile id (UUID), or an email address
#   - the retired internal product name
#   - a data file (.csv, .tsv, .xlsx, .parquet, .duckdb) outside a synthetic/ folder
# Warns (does not fail) on calendar dates, which need a human read.
#
# The denylist is NOT in this repository. It lives in the private companion repo and is
# found at ../portfolio-private/denylist/denylist.txt, or at the path in the
# PORTFOLIO_DENYLIST environment variable. Without it the scan fails, unless run with
# --allow-no-denylist (for machines that never see real data).
#
# Usage: Rscript tools/privacy_scan.R [--allow-no-denylist]

args <- commandArgs(trailingOnly = TRUE)
allow_no_denylist <- "--allow-no-denylist" %in% args

repo_root <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE)
setwd(repo_root)

files <- system2("git", c("ls-files", "--cached", "--others", "--exclude-standard"),
                 stdout = TRUE)
files <- files[file.exists(files)]
# This script describes the patterns it hunts for, so it is exempt from the text checks.
text_exempt <- c("tools/privacy_scan.R")

denylist_path <- Sys.getenv("PORTFOLIO_DENYLIST",
                            file.path(dirname(repo_root), "portfolio-private",
                                      "denylist", "denylist.txt"))
denylist <- character(0)
if (file.exists(denylist_path)) {
  denylist <- readLines(denylist_path, warn = FALSE, encoding = "UTF-8")
  denylist <- unique(trimws(denylist))
  denylist <- denylist[nchar(denylist) > 0 & !startsWith(denylist, "#")]
} else if (!allow_no_denylist) {
  cat("PRIVACY SCAN FAILED: denylist not found at", denylist_path, "\n")
  cat("Generate it with portfolio-private/real/make_denylist.R, or set PORTFOLIO_DENYLIST.\n")
  quit(status = 1)
} else {
  cat("WARNING: no denylist; name checks skipped.\n")
}

patterns <- list(
  "TrackMan player id" = "\\b10[0-9]{8}\\b",
  "UUID (VALD profile id)" = "\\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\b",
  "email address" = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
  "retired product name" = "\\bTRAQ\\b"
)
date_pattern <- "\\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\\b"
data_ext <- "\\.(csv|tsv|xlsx|xls|parquet|duckdb|feather|rds)$"
binary_ext <- "\\.(png|jpg|jpeg|gif|pdf|ico|woff2?|ttf|zip)$"

failures <- character(0)
warnings_out <- character(0)

# Lowercased denylist entries, matched as whole phrases.
deny_lower <- tolower(denylist)
deny_regex <- if (length(deny_lower) > 0) {
  paste0("(^|[^a-z])\\Q", deny_lower, "\\E([^a-z]|$)")   # \Q..\E = literal text
} else {
  character(0)
}

for (f in files) {
  if (grepl(data_ext, f, ignore.case = TRUE) && !grepl("(^|/)synthetic/", f)) {
    failures <- c(failures, sprintf("%s: data file outside a synthetic/ folder", f))
  }
  # renv.lock and renv/ are machine-written package metadata (maintainer emails included).
  if (grepl(binary_ext, f, ignore.case = TRUE) || f %in% text_exempt ||
      f == "renv.lock" || startsWith(f, "renv/")) next
  lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"),
                    error = function(e) character(0))
  if (length(lines) == 0) next
  lower <- tolower(lines)

  for (label in names(patterns)) {
    hit <- grep(patterns[[label]], lines, perl = TRUE)
    for (i in hit) failures <- c(failures, sprintf("%s:%d: %s", f, i, label))
  }
  for (k in seq_along(deny_regex)) {
    hit <- grep(deny_regex[k], lower, perl = TRUE)
    for (i in hit) failures <- c(failures, sprintf("%s:%d: denylisted name", f, i))
  }
  if (basename(f) != "CHANGELOG.md") {
    hit <- grep(date_pattern, lines, perl = TRUE)
    for (i in hit) warnings_out <- c(warnings_out, sprintf("%s:%d: calendar date (check by eye)", f, i))
  }
}

cat(sprintf("Privacy scan: %d files, %d denylist entries.\n", length(files), length(denylist)))
if (length(warnings_out) > 0) {
  cat("Warnings:\n")
  cat(paste0("  ", warnings_out, "\n"), sep = "")
}
if (length(failures) > 0) {
  cat("PRIVACY SCAN FAILED:\n")
  cat(paste0("  ", failures, "\n"), sep = "")
  quit(status = 1)
}
cat("Privacy scan passed.\n")
