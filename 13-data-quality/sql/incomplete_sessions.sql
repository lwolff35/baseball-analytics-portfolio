-- incomplete_sessions: force-plate sessions saved with fewer trials than the protocol.
-- A session is one athlete, one test, one timestamp. {expected_trials} comes from checks.yml.
WITH sessions AS (
    SELECT athlete_id,
           test_type,
           test_ts_utc,
           COUNT(*) AS trials
    FROM force_trials
    GROUP BY athlete_id, test_type, test_ts_utc
)
SELECT f.trial_id AS key,
       s.trials
FROM force_trials AS f
JOIN sessions AS s
  ON s.athlete_id = f.athlete_id
 AND s.test_type = f.test_type
 AND s.test_ts_utc = f.test_ts_utc
WHERE s.trials < {expected_trials}
ORDER BY f.trial_id;
