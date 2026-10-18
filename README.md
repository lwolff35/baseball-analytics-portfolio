# Baseball Analytics Portfolio

Applied analytics and Bayesian modeling projects by **Luke Wolff**, Director of Operations &
Analytics at BSF Performance, a baseball training facility.

Every project here started from a real question at the facility: is a retest change real,
can every number in a coach report be trusted, how should a pitcher's velocity develop. The
code is written to run end to end on data anyone can access.

## About the data

**No real athlete data is in this repository.** Athletes at the facility are mostly minors,
and their data stays private. Each project uses one of two sources:

- **Synthetic data** simulated to match the shape of the facility's tables (column names,
  ranges, missingness patterns), with no real values.
- **Public MLB data** (Statcast via Baseball Savant).

Where a write-up cites what the real data showed, the figure is a rounded aggregate across
many athletes, never an individual.

## Projects

| # | Project | Question | Data | Status |
|---|---|---|---|---|
| 13 | [Data Quality Layer](13-data-quality/) ([write-up](13-data-quality/report.html)) | Can every number in a report be trusted, and how do we know? | Synthetic | Checks and tests done; real-data run in progress |

## Stack

R (tidyverse, pointblank, brms/Stan, ggdist), SQL (DuckDB), Quarto. Package versions are
pinned with `renv` (`renv::restore()` reproduces the environment).

## Contact

References and a walkthrough of the private implementation are available on request.
