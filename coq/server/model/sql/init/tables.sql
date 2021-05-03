BEGIN;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------


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


-- !! sources 1:N completions
-- !! files   1:N completions
-- Should be vaccumed by keeping last n rows, per source
CREATE TABLE IF NOT EXISTS completions (
  rowid         INTEGER NOT NULL PRIMARY KEY,
  source        TEXT    NOT NULL REFERENCES sources  (source)   ON DELETE CASCADE,
  filename      TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  response_time REAL,   -- if timeout -> NULL
  num_items     INTEGER -- if timeout -> NULL
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
  prefix        TEXT    NOT NULL,
  affix         TEXT    NOT NULL,
  content       TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS insertions_prefix_affix  ON insertions (prefix, affix);
CREATE INDEX IF NOT EXISTS insertions_completion_id ON insertions (completion_id);
CREATE INDEX IF NOT EXISTS insertions_content       ON insertions (content);


--------------------------------------------------------------------------------
-- DEBUG VIEWS
--------------------------------------------------------------------------------


CREATE VIEW IF NOT EXISTS words_debug_view AS
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
    words.word;


CREATE VIEW IF NOT EXISTS completions_debug_view AS
  SELECT
    completions.source        AS source,
    files.filetype            AS filetype,
    files.project             AS project,
    files.filename            AS filename,
    completions.response_time AS response_time,
    completions.num_items     AS num_items
  FROM completions
  JOIN files
  ON
    files.filename = completions.filename
  ORDER BY
    completions.source,
    files.filetype,
    files.project,
    files.filename,
    completions.response_time,
    completions.num_items;


CREATE VIEW IF NOT EXISTS insertions_debug_view AS
  SELECT
    completions.source AS source,
    files.filetype     AS filetype,
    files.project      AS project,
    files.filename     AS filename,
    insertions.prefix  AS prefix,
    insertions.suffix  AS suffix,
    insertions.content AS content
  FROM insertions
  JOIN completions
  ON
    completions.rowid = insertions.completion_id
  JOIN files
  ON
    files.filename = completions.filename
  ORDER BY
    completions.source,
    files.project,
    files.filetype,
    files.filename,
    insertions.prefix,
    insertions.suffix,
    insertions.content;


--------------------------------------------------------------------------------
-- OLAP VIEWS
--------------------------------------------------------------------------------


CREATE VIEW IF NOT EXISTS source_total_view AS
  SELECT
    source   AS source,
    COUNT(*) AS totals
  FROM
    source
  GROUP BY
    source;


CREATE VIEW IF NOT EXISTS source_response_time_view AS
  SELECT
    source             AS source,
    AVG(response_time) AS avg_response_time
  FROM completions
  GROUP BY
    source;


CREATE VIEW IF NOT EXISTS source_timeout_view AS
  SELECT
    source   AS source,
    COUNT(*) AS timeouts
  FROM completions
  GROUP BY
    source
  HAVING
    response_time IS NULL;


CREATE VIEW IF NOT EXISTS most_inserted_trigger_view AS
  SELECT
    insertions.prefix || insertions.suffix AS trigger,
    COUNT(*)                               AS occurrences
  FROM insertions
  JOIN completions
  ON
    completions.rowid = insertions.completion_id
  JOIN
    files
  ON
    files.filename = completions.filename
  GROUP BY
    files.filetype,
    insertions.prefix,
    insertions.suffix
  ORDER BY
    occurrences;


CREATE VIEW IF NOT EXISTS most_inserted_content_view AS
  SELECT
    insertions.content AS content,
    COUNT(*)           AS occurrences
  FROM insertions
  JOIN completions
  ON
    completions.rowid = insertions.completion_id
  JOIN
    files
  ON
    files.filename = completions.filename
  GROUP BY
    files.filetype,
    insertions.content
  ORDER BY
    occurrences;


--------------------------------------------------------------------------------
-- OLTP VIEWS
--------------------------------------------------------------------------------


CREATE VIEW IF NOT EXISTS count_words_by_project_filetype_view AS
  SELECT
    files.filetype AS filetype,
    files.project  AS project,
    words.word     AS word,
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


CREATE VIEW IF NOT EXISTS count_words_by_filetype_view AS
  SELECT
    files.filetype AS filetype,
    words.word     AS word,
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
    words.word;


CREATE VIEW IF NOT EXISTS count_words_by_file_lines_view AS
  SELECT
    files.filename          AS filename,
    word_locations.line_num AS line_num,
    words.word              AS word,
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


END;
