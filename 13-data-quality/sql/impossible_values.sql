-- impossible_values: measurements outside what is physically possible.
-- Limits come from checks.yml. A NULL is not impossible (missing is a different check).
SELECT 'pitches' AS source, pitch_uid AS key, 'rel_speed_mph' AS field, rel_speed_mph AS value
FROM pitches
WHERE rel_speed_mph NOT BETWEEN {rel_speed_mph_min} AND {rel_speed_mph_max}

UNION ALL
SELECT 'pitches', pitch_uid, 'spin_rpm', spin_rpm
FROM pitches
WHERE spin_rpm NOT BETWEEN {spin_rpm_min} AND {spin_rpm_max}

UNION ALL
SELECT 'force_trials', trial_id, 'jump_height_in', jump_height_in
FROM force_trials
WHERE jump_height_in NOT BETWEEN {jump_height_in_min} AND {jump_height_in_max}

UNION ALL
SELECT 'rom', rom_id, 'degrees', degrees
FROM rom
WHERE degrees NOT BETWEEN {rom_degrees_min} AND {rom_degrees_max}

ORDER BY source, key;
