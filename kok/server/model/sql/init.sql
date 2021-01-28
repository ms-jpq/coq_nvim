BEGIN;


-- Should be vacuumed if no files references filetype
CREATE TABLE filetypes (
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
CREATE TABLE files (
  filename TEXT NOT NULL PRIMARY KEY,
  project  TEXT NOT NULL REFERENCES projects  (project)  ON DELETE CASCADE,
  filetype TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX files_filetype ON filetypes (filetype);


-- Index for words in files
-- Should be vacuumed when no longer in word_locations
CREATE TABLE words (
  word  TEXT NOT NULL PRIMARY KEY,
  nword TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX words_nword ON words (nword);


-- !! words 1:N word_locations
-- !! files 1:N word_locations
-- Store word location in files
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE word_locations (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  word     TEXT    NOT NULL REFERENCES words (word)     ON DELETE CASCADE,
  line_num INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX word_locations_filename ON word_locations (filename);
CREATE INDEX word_locations_word     ON word_locations (word);
CREATE INDEX word_locations_line_num ON word_locations (line_num);


-- Store inserted content
-- Should be vacuumed if not in `insertions`
CREATE TABLE inserted (
  content TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


-- !! files    1:N insertions
-- !! inserted 1:N insertions
-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE insertions (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  prefix   TEXT    NOT NULL,
  affix    TEXT    NOT NULL,
  filename TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  content  TEXT    NOT NULL REFERENCES inserted (content)  ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX insertions_prefix_affix ON insertions (prefix, affix);


-- Words debug view
CREATE VIEW words_debug_view AS (
  SELECT
    files.project           AS project,
    filetypes.filetype      AS filetype,
    files.filename          AS filename,
    word_locations.line_num AS line_num,
    words.word              AS word,
    words.nword             AS nword
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  ORDER BY
    files.project,
    filetypes.filetype,
    files.filename,
    word_locations.line_num,
    words.word
);


CREATE VIEW count_words_by_filetype_view AS (
  SELECT
    COUNT(*)       AS w_count,
    words.word     AS word,
    files.filetype AS filetype
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  GROUP BY
    words.word,
    files.filetype
);


CREATE VIEW count_words_by_file_lines_view AS (
  SELECT
    COUNT(*)                AS w_count,
    words.word              AS word,
    word_locations.line_num AS line_num,
    files.filename          AS filename
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  GROUP BY
    words.word,
    word_locations.line_num,
    files.filename
);


END;
