-- orphan_links: identity links pointing at an athlete who is not on the roster.
SELECT l.athlete_id AS key,
       l.tracker_id
FROM tracker_links AS l
LEFT JOIN roster AS r
       ON r.athlete_id = l.athlete_id
WHERE r.athlete_id IS NULL
ORDER BY l.athlete_id;
