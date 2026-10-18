# 13. Data Quality Layer

**Question:** Can every number in a coach-facing report be trusted, and how do we know?

A training facility's analytics platform pulls from several sources at once: a pitch
tracker, force plates, hand-entered range-of-motion measurements and a roster. Each source
fails in its own way, and most failures are silent: the report still renders, it is just
wrong. This project is an automated check suite that catches those failures before a
number reaches a report, plus a test harness that proves each check works.

## The checks

| Check | Catches | How |
|---|---|---|
| `empty_columns` | A field that is never filled (the real tracker's team field was 0% populated, so anything reading it was silently wrong) | R |
| `impossible_values` | Velocity, spin, jump height or range of motion outside physical limits | SQL, and independently in `pointblank` |
| `duplicate_rows` | The same pitch loaded twice when two exports overlap | SQL |
| `unlinked_tracker_ids` | Pitches from a tracker id mapped to no athlete | SQL |
| `orphan_links` | Identity links pointing at an athlete missing from the roster | SQL |
| `timezone_day_shift` | Evening tests filed under the next day because the UTC date was used instead of the local date | R |
| `biased_tag_missingness` | Pitch-type tags missing **non-randomly** (e.g. faster pitchers tagged less), which biases every pitch-type metric | R (correlation across pitchers) |
| `device_drift` | A force plate whose readings shift over time (calibration slipping) | R (recent vs earlier sessions, adjusted for athlete level) |
| `incomplete_sessions` | Force sessions saved with fewer trials than the protocol | SQL |
| `out_of_range_dates` | Dates before the system existed or after the run date | SQL |

Every threshold lives in [`checks.yml`](checks.yml), not in code.

## Proving the checks work

The simulator in [`synthetic/simulate_facility.R`](../synthetic/simulate_facility.R) builds
a fake facility (150 athletes, ~15,000 pitches, ~700 force trials) shaped like a real one.
With `inject_errors = TRUE` it plants one family of error per check and writes an answer
key of exactly what it planted.

- **Rule checks** must pass on clean data and flag exactly the planted rows on every seed.
- **Statistical checks** can be wrong on any single dataset, so they are judged by their
  error rates across 200 simulated facilities ([`validate_error_rates.R`](validate_error_rates.R)):

| Statistical check | Result (200 simulated facilities) |
|---|---|
| Tag-missingness bias: false alarms on clean data | 1.0% |
| Tag-missingness bias: planted bias detected | 100% |
| Device drift: false alarms with no drift | 0.0% |
| Device drift: +5% / +10% / +15% / +20% drift detected | 8% / 50% / 87% / 99.5% |

**What the drift numbers mean:** at this facility's testing volume, the drift check is
reliable only for shifts of about 15% or more. Smaller calibration problems need a
different tool, such as a scheduled reference test on each plate, not a smarter statistic.

## What checks like these found in real data

The same checks, run on a real facility's archive (~200,000 pitches, ~1,900 force-plate
trials). Rounded figures; 5 of the 10 checks found real problems:

- The tracker's team field and all three game-outcome fields were **never** populated, so
  athlete level had to come from the force-plate system's roster instead.
- About **3 in 4** tracker ids (two-thirds of pitches) link to no athlete in the
  force-plate system, which limits any analysis that needs age or level.
- About **1 in 6** force-plate athlete-days land on the wrong calendar day if read the
  simple way: evening tests stored in UTC roll into the next day.
- About **1 in 9** three-trial force tests were saved with fewer than three trials.
- Small: 35 impossible spin readings (under 0.1%), 0.3% of pitch rows with no pitch id, no
  duplicated pitches.
- **A documented "fact" that didn't hold:** **56%** of pitches carry no pitch-type tag. An
  earlier analysis found slower throwers tagged more (r = -0.29); on the full archive the
  bias check finds r = -0.05 and passes. What is uneven is who gets tagged: the facility's
  own athletes ~69% of the time, other pitchers ~43%. An all-pitch 95th percentile tracks
  tagged-fastball velocity at **r = 0.997** (mean error 0.5 mph), so velocity doesn't
  depend on tags.
- The real run also found two bugs in the checks themselves (now fixed, each with a test).

## Run it

From the repository root, after `renv::restore()`:

```
Rscript 13-data-quality/run_demo.R                          # clean vs planted errors
Rscript -e 'testthat::test_dir("13-data-quality/tests")'    # full test suite (~1.5 min)
Rscript 13-data-quality/validate_error_rates.R 200          # error-rate sweep (~8 min)
```

## Data

Synthetic only. See the repository README.
