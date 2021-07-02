BEGIN;


CREATE TABLE IF NOT EXISTS buffers (
  rowid     INTEGER NOT NULL PRIMARY KEY,
  filetype  TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS buffers_filetype ON buffers (filetype);


CREATE TABLE IF NOT EXISTS lines (
  rowid     INTEGER NOT NULL PRIMARY KEY,
  buffer_id INTEGER NOT NULL REFERENCES buffers (rowid) ON DELETE CASCADE,
  line_num  INTEGER NOT NULL,
  line      TEXT    NOT NULL
  -- TODO -- How to update line_num from back -> front in a single query
  -- UNIQUE(filename, line_num)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS liness_buffer_id ON lines (buffer_id);
CREATE INDEX IF NOT EXISTS lines_line_num   ON lines (line_num);


CREATE TABLE IF NOT EXISTS words (
  line_id INTEGER NOT NULL REFERENCES lines (rowid) ON DELETE CASCADE,
  word    TEXT    NOT NULL,
  lword   TEXT    NOT NULL AS (X_LOWER(word)) STORED
);
CREATE INDEX IF NOT EXISTS words_line_id ON words (line_id);
CREATE INDEX IF NOT EXISTS words_word    ON words (word);
CREATE INDEX IF NOT EXISTS words_lword   ON words (lword);


-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
CREATE TABLE IF NOT EXISTS insertions (
  rowid   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  content TEXT    NOT NULL UNIQUE
);


CREATE VIEW IF NOT EXISTS filetype_wordcount_view AS
SELECT
  buffers.filetype  AS filetype,
  words.word        AS word,
  COUNT(words.word) AS wordcount
FROM files
JOIN words
ON
  words.filename = buffers.filename
GROUP BY
  buffers.filetype,
  words.word;
  

END;
