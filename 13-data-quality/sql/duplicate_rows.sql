-- duplicate_rows: the same pitch loaded more than once.
-- Each pitch has a unique id from the tracker; seeing it twice means two exports overlapped.
-- Rows with no id at all are left out: GROUP BY would lump them into one fake duplicate
-- (found on the real archive).
SELECT pitch_uid AS key,
       COUNT(*)  AS copies
FROM pitches
WHERE pitch_uid IS NOT NULL
GROUP BY pitch_uid
HAVING COUNT(*) > 1
ORDER BY pitch_uid;
