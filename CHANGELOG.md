# Changelog

Public record of what shipped, newest first.

## 2026-10-17

- Project 13: checks run on a real facility's archive (privately); rounded results added
  to the write-up. The run found two bugs in the checks (crash on an empty table; rows with
  no pitch id counted as one duplicate), both fixed with tests, and showed an earlier
  tagging-bias finding does not hold on the full archive.
- Project 13: facility simulator with planted errors, 10 data quality checks (SQL in
  DuckDB, R, and a `pointblank` validity report), a test suite, and an error-rate sweep
  over 200 simulated facilities.
- Bayesian toolchain (brms + CmdStan) added to the pinned environment.
- Repository set up: project layout, pinned R environment (`renv`), and a privacy scan that
  runs on every commit (`tools/privacy_scan.R`).
- Project 13 (Data Quality Layer) scoped.
