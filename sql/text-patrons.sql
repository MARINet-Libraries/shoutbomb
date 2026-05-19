SELECT
	REGEXP_REPLACE(r.phone_number, '[- \\.]', '', 'g') AS phone_number,
	v.barcode,
	iii_language_pref_code
FROM
	sierra_view.patron_view AS v
	JOIN sierra_view.patron_record_phone AS r ON (v.id = r.patron_record_id)
	JOIN sierra_view.patron_record_phone_type AS ty ON (
		r.patron_record_phone_type_id = ty.id
	)
	-- p is field tag for the telephone2 var field
WHERE
	ty.code = 'p'
	AND v.notification_medium_code = 't'
ORDER BY
	v.barcode;
