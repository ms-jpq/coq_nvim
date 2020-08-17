SELECT
  old_prefix,
  new_prefix,
  old_suffix,
  new_suffix
FROM medits
WHERE
  medits.suggestions_id = ?
