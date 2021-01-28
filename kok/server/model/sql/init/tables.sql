BEGIN;


-- Should be vaccumed?
CREATE TABLE IF NOT EXISTS sources (
  source TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


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
CREATE INDEX files_filetype ON filetypes (filetype);


-- Index for words in files
-- Should be vacuumed when no longer in word_locations
CREATE TABLE IF NOT EXISTS words (
  word  TEXT NOT NULL PRIMARY KEY,
  lword TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX words_lword ON words (lword);


-- !! words 1:N word_locations
-- !! files 1:N word_locations
-- Store word location in files
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE IF NOT EXISTS word_locations (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  word     TEXT    NOT NULL REFERENCES words (word)     ON DELETE CASCADE,
  line_num INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX word_locations_filename ON word_locations (filename);
CREATE INDEX word_locations_word     ON word_locations (word);
CREATE INDEX word_locations_line_num ON word_locations (line_num);


-- !! sources 1:N insertions
-- !! files   1:N insertions
-- Stores insertion history
-- Should be vacuumed by only keeping last n rows
-- Should be vacuumed by foreign key constraints on `files`
CREATE TABLE IF NOT EXISTS insertions (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  source   TEXT    NOT NULL REFERENCES sources (source)   ON DELETE CASCADE,
  filename TEXT    NOT NULL REFERENCES files   (filename) ON DELETE CASCADE,
  prefix   TEXT    NOT NULL,
  affix    TEXT    NOT NULL,
  content  TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX insertions_prefix_affix ON insertions (prefix, affix);
CREATE INDEX insertions_filename     ON insertions (filename);
CREATE INDEX insertions_content      ON insertions (content);


-- !! sources 1:N completions
-- !! files   1:N completions
-- Should be vaccumed by keeping last n rows, per source
CREATE TABLE IF NOT EXISTS completions (
  rowid        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  source       TEXT    NOT NULL REFERENCES sources  (source)   ON DELETE CASCADE,
  filename     TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  time_elapsed REAL,   -- if timeout -> NULL
  num_items    INTEGER -- if timeout -> NULL
) WITHOUT ROWID;
CREATE INDEX completions_source   ON completions (source);
CREATE INDEX completions_filename ON completions (filename);


---             ---
--- DEBUG VIEWS ---
---             ---


-- Words debug view
CREATE VIEW IF NOT EXISTS words_debug_view AS (
  SELECT
    files.project           AS project,
    files.filetype          AS filetype,
    files.filename          AS filename,
    word_locations.line_num AS line_num,
    words.word              AS word,
    words.lword             AS lword
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  ORDER BY
    files.project,
    files.filetype,
    files.filename,
    word_locations.line_num,
    words.word
);


CREATE VIEW IF NOT EXISTS insertions_debug_view AS (
  SELECT
    files.project      AS project,
    files.filetype     AS filetype,
    files.filename     AS filename,
    insertions.content AS content,
    insertions.prefix  AS prefix,
    insertions.suffix  AS suffix
  FROM insertions
  JOIN files
  ON
    files.filename = insertions.filename
  ORDER BY
    files.project,
    files.filetype,
    files.filename,
    insertions.content,
    insertions.prefix,
    insertions.suffix
);


CREATE VIEW IF NOT EXISTS completions_debug_view AS (
  SELECT
    completions.source       AS source,
    files.filetype           AS filetype,
    files.project            AS project,
    files.filename           AS filename,
    completions.time_elapsed AS time_elapsed,
    completions.num_items    AS num_items
  FROM completions
  JOIN files
  ON
    files.filename = completions.filename
  ORDER BY
    completions.source,
    files.filetype,
    files.project,
    files.filename,
    completions.time_elapsed,
    completions.num_items
);


---            ---
--- OLAP VIEWS ---
---            ---




---            ---
--- OLTP VIEWS ---
---            ---


CREATE VIEW IF NOT EXISTS count_words_by_project_filetype_view AS (
  SELECT
    COUNT(*)       AS w_count,
    words.word     AS word,
    files.project  AS project,
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
    files.project,
    files.filetype
);



CREATE VIEW IF NOT EXISTS count_words_by_filetype_view AS (
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


CREATE VIEW IF NOT EXISTS count_words_by_file_lines_view AS (
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
