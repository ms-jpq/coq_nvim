BEGIN;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------


-- TMP!
CREATE TEMP TABLE buffers (
  buffer INTEGER NOT NULL PRIMARY KEY,
  tick   INTEGER NOT NULL
) WITHOUT ROWID;


-- TMP!
-- !! buffer 1:N lines
CREATE TEMP TABLE lines (
  buffer   INTEGER NOT NULL REFERENCES buffers (buffer) ON DELETE CASCADE,
  line_num INTEGER NOT NULL,
  line     TEXT    NOT NULL,
  UNIQUE (buffer, line_num)
);
CREATE INDEX IF NOT EXISTS lines_line_num ON lines (line_num);


-- Should be vacuumed if no files references filetype
CREATE TABLE IF NOT EXISTS filetypes (
  filetype TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


-- !! filetypes 1:N files
-- Should be vacuumed if file no longer exists, once at beginning
-- Should be vacuumed if is ephemeral?
CREATE TABLE IF NOT EXISTS files (
  filename TEXT NOT NULL PRIMARY KEY,
  filetype TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_filetype ON filetypes (filetype);


-- Index for words in files
-- Should be vacuumed when no longer in word_locations
CREATE TABLE IF NOT EXISTS words (
  word  TEXT NOT NULL PRIMARY KEY,
  lword TEXT NOT NULL AS (X_LOWER(word)) STORED
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS words_lword ON words (lword);


-- !! words 1:N word_locations
-- !! files 1:N word_locations
-- Store word location in files
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE IF NOT EXISTS word_locations (
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  word     TEXT    NOT NULL REFERENCES words (word)     ON DELETE CASCADE,
  line_num INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS word_locations_filename ON word_locations (filename);
CREATE INDEX IF NOT EXISTS word_locations_word     ON word_locations (word);
CREATE INDEX IF NOT EXISTS word_locations_line_num ON word_locations (line_num);


-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
CREATE TABLE IF NOT EXISTS insertions (
  rowid         INTEGER NOT NULL PRIMARY KEY,
  content       TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS insertions_content ON insertions (content);


END;
