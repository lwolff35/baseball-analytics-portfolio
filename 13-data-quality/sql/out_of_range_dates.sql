-- out_of_range_dates: pitch sessions dated before the tracker existed or after the run date.
SELECT pitch_uid    AS key,
       session_date
FROM pitches
WHERE session_date < DATE '{earliest_valid}'
   OR session_date > DATE '{latest_valid}'
ORDER BY pitch_uid;
