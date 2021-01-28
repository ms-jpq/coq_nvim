BEGIN;


CREATE TABLE filetypes (
  filetype TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE files (
  filename TEXT NOT NULL PRIMARY KEY,
  filetype TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX files_filetype ON filetypes (filetype);


CREATE TABLE ephemeral_files (
  filename TEXT NOT NULL PRIMARY KEY REFERENCES files (filename) ON DELETE CASCADE
) WITHOUT ROWID;


CREATE TABLE words (
  word  TEXT NOT NULL PRIMARY KEY,
  nword TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX words_nword ON words (nword);


CREATE TABLE word_locations (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  word     TEXT    NOT NULL REFERENCES words (word)     ON DELETE CASCADE,
  line_num INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX word_locations_filename ON word_locations (filename);
CREATE INDEX word_locations_word     ON word_locations (word);
CREATE INDEX word_locations_line_num ON word_locations (line_num);


CREATE TABLE inserted (
  content TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE insertion_contexts (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  prefix   TEXT    NOT NULL,
  affix    TEXT    NOT NULL,
  filename TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  content  TEXT    NOT NULL REFERENCES inserted (content)  ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX insertion_contexts_prefix_affix ON insertion_contexts (prefix, affix);


CREATE TABLE insertions (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filename TEXT    NOT NULL REFERENCES files    (filename) ON DELETE CASCADE,
  content  TEXT    NOT NULL REFERENCES inserted (content)  ON DELETE CASCADE
) WITHOUT ROWID;


CREATE VIEW main_view AS (
  SELECT
    words.word              AS word,
    words.nword             AS nword,
    word_locations.line_num AS line_num,
    files.filename          AS filename,
    filetypes.filetype      AS filetype
  FROM words
  JOIN word_locations
  ON
    word_locations.word = words.word
  JOIN files
  ON
    files.filename = word_locations.filename
  JOIN filetypes
  ON
    filetypes.filetype = files.filetype
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
