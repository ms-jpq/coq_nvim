BEGIN;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------


-- Should be vacuumed if no files references filetype
CREATE TABLE IF NOT EXISTS filetypes (
  filetype TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


-- Probably just cwd
-- Should be vacuumed if folder not longer exists, once at beginning
CREATE TABLE projects (
  project TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


-- !! projects  1:N files
-- !! filetypes 1:N files
-- Should be vacuumed if file no longer exists, once at beginning
-- Should be vacuumed by foreign key constraints on `projects`
-- Should be vacuumed if is ephemeral?
CREATE TABLE IF NOT EXISTS files (
  filename TEXT NOT NULL PRIMARY KEY,
  project  TEXT NOT NULL REFERENCES projects  (project)  ON DELETE CASCADE,
  filetype TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_filetype ON filetypes (filetype);


-- Index for words in files
-- Should be vacuumed when no longer in word_locations
CREATE TABLE IF NOT EXISTS words (
  word  TEXT NOT NULL PRIMARY KEY,
  lword TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS words_lword ON words (lword);


-- !! words 1:N word_locations
-- !! files 1:N word_locations
-- Store word location in files
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE IF NOT EXISTS word_locations (
  rowid    INTEGER NOT NULL PRIMARY KEY,
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  word     TEXT    NOT NULL REFERENCES words (word)     ON DELETE CASCADE,
  line_num INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS word_locations_filename ON word_locations (filename);
CREATE INDEX IF NOT EXISTS word_locations_word     ON word_locations (word);
CREATE INDEX IF NOT EXISTS word_locations_line_num ON word_locations (line_num);


-- !! files   1:N completions
-- Should be vaccumed by keeping last n rows, per source
CREATE TABLE IF NOT EXISTS completions (
  rowid         INTEGER NOT NULL PRIMARY KEY,
  filename      TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  response_time REAL,   -- if timeout -> NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS completions_source   ON completions (source);
CREATE INDEX IF NOT EXISTS completions_filename ON completions (filename);


-- !! completions 1:1 insertions
-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
-- Should be vacuumed by foreign key constraints on `completions`
CREATE TABLE IF NOT EXISTS insertions (
  rowid         INTEGER NOT NULL PRIMARY KEY,
  completion_id INTEGER NOT NULL UNIQUE REFERENCES completions (rowid) ON DELETE CASCADE,
  content       TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS insertions_content ON insertions (content);


--------------------------------------------------------------------------------
-- OLTP VIEWS
--------------------------------------------------------------------------------


CREATE VIEW IF NOT EXISTS words_by_insertion_view AS
  SELECT
    words.word AS word,
  FROM words


CREATE VIEW IF NOT EXISTS words_by_project_filetype_view AS
  SELECT
    words.word     AS word,
    files.filetype AS filetype,
    files.project  AS project,
    COUNT(*)       AS w_count
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  GROUP BY
    files.filetype,
    files.project,
    words.word;


CREATE VIEW IF NOT EXISTS words_by_file_lines_view AS
  SELECT
    words.word              AS word,
    files.filename          AS filename,
    word_locations.line_num AS line_num,
    COUNT(*)                AS w_count
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  GROUP BY
    files.filename,
    word_locations.line_num,
    words.word;


CREATE VIEW IF NOT EXISTS metrics_view AS
  SELECT
    words.word AS word,

  FROM words
  JOIN words_by_project_filetype_view
  ON
    words_by_project_filetype_view.word = word.word
  JOIN words_by_file_lines_view
  ON
    words_by_file_lines_view.word = word.word;


END;
