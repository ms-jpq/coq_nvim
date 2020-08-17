SELECT
  begin_row,
  begin_col,
  end_row,
  end_col,
  text
FROM ledits
WHERE
  ledits.suggestions_id = ?
