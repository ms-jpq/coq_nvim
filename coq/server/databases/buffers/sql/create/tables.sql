BEGIN;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------


CREATE TABLE IF NOT EXISTS buffers (
  buffer_id INTEGER NOT NULL PRIMARY KEY,
  filetype  TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS buffers_filetype ON buffers (filetype);


CREATE TABLE IF NOT EXISTS words (
  buffer_id INTEGER NOT NULL REFERENCES buffer_id (buffer_id) ON DELETE CASCADE,
  line_num  INTEGER NOT NULL,
  word      TEXT    NOT NULL,
  lword     TEXT    NOT NULL AS (X_LOWER(word)) STORED
);
CREATE INDEX IF NOT EXISTS words_buffer_id ON words (buffer_id);
CREATE INDEX IF NOT EXISTS words_word      ON words (word);
CREATE INDEX IF NOT EXISTS words_lword     ON words (lword);
CREATE INDEX IF NOT EXISTS words_line_num  ON words (line_num);


CREATE TABLE IF NOT EXISTS lines (
  buffer_id INTEGER NOT NULL REFERENCES buffer_id (buffer_id) ON DELETE CASCADE,
  line     TEXT    NOT NULL,
  line_num INTEGER NOT NULL
  -- TODO -- How to update line_num from back -> front in a single query
  -- UNIQUE(filename, line_num)
);
CREATE INDEX IF NOT EXISTS liness_buffer_id ON lines (buffer_id);
CREATE INDEX IF NOT EXISTS lines_line_num   ON lines (line_num);


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
  

CREATE TEMP TABLE IF NOT EXISTS tmp_for_metrics (
  rowid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  word  TEXT NOT NULL
);


END;
