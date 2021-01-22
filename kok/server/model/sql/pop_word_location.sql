INSERT INTO word_locations (word_id, file_id, line_num)
SELECT 
  (
    SELECT rowid
    FROM words
    WHERE
      words.word = ?
  ) AS word_id,
  (
    SELECT rowid
    FROM files
    WHERE
      filename = ?
  ) AS file_id,
  ? AS line_num


