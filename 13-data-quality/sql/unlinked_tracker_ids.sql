-- unlinked_tracker_ids: pitches from a tracker id that maps to no athlete.
-- Those pitches can't reach anyone's report until someone links the id.
SELECT p.tracker_id AS key,
       COUNT(*)     AS pitches
FROM pitches AS p
LEFT JOIN tracker_links AS l
       ON l.tracker_id = p.tracker_id
WHERE l.tracker_id IS NULL
GROUP BY p.tracker_id
ORDER BY p.tracker_id;
