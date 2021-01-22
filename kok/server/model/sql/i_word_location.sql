INSERT INTO word_locations (word_id, file_id, line_num)
SELECT 
  (
    SELECT rowid
    FROM words
    WHERE
      word = :word
  ) AS word_id,
  (
    SELECT rowid
    FROM files
    WHERE
      filename = :filename
  ) AS file_id,
  :line_num AS line_num
