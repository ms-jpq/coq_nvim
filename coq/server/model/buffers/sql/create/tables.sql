BEGIN;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------


CREATE TABLE IF NOT EXISTS files (
  filename TEXT NOT NULL PRIMARY KEY,
  filetype TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_filetype ON files (filetype);


CREATE TABLE IF NOT EXISTS words (
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  line_num INTEGER NOT NULL,
  word     TEXT    NOT NULL,
  lword    TEXT    NOT NULL AS (X_LOWER(word)) STORED
);
CREATE INDEX IF NOT EXISTS words_filename ON words (filename);
CREATE INDEX IF NOT EXISTS words_word     ON words (word);
CREATE INDEX IF NOT EXISTS words_lword    ON words (lword);
CREATE INDEX IF NOT EXISTS words_line_num ON words (line_num);


CREATE TABLE IF NOT EXISTS lines (
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  line     TEXT    NOT NULL,
  line_num INTEGER NOT NULL
  -- TODO -- How to update line_num from back -> front in a single query
  -- UNIQUE(filename, line_num)
);
CREATE INDEX IF NOT EXISTS lines_filename ON lines (filename);
CREATE INDEX IF NOT EXISTS lines_line_num ON lines (line_num);


-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
CREATE TABLE IF NOT EXISTS insertions (
  rowid   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  content TEXT    NOT NULL UNIQUE
);


CREATE TEMP TABLE IF NOT EXISTS tmp_for_metrics (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL,
  filename TEXT    NOT NULL,
  line_num INTEGER NOT NULL,
  content  TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS tmp_for_metrics_filetype ON tmp_for_metrics (filetype);
CREATE INDEX IF NOT EXISTS tmp_for_metrics_filename ON tmp_for_metrics (filename);
CREATE INDEX IF NOT EXISTS tmp_for_metrics_line_num ON tmp_for_metrics (line_num);
CREATE INDEX IF NOT EXISTS tmp_for_metrics_content  ON tmp_for_metrics (content);


END;
