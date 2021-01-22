BEGIN;


CREATE TABLE filetypes (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL UNIQUE
) WITHOUT ROWID;


CREATE TABLE files (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filename    TEXT    NOT NULL UNIQUE,
  filetype_id INTEGER NOT NULL REFERENCES filetypes (rowid) ON DELETE CASCADE
) WITHOUT ROWID;


CREATE TABLE words (
  rowid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  word  TEXT    NOT NULL UNIQUE,
  nword TEXT    NOT NULL,
) WITHOUT ROWID;
CREATE INDEX words_nword ON words (nword);


CREATE TABLE word_locations (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  word_id  INTEGER NOT NULL REFERENCES words (rowid) ON DELETE CASCADE,
  file_id  INTEGER NOT NULL REFERENCES files (rowid) ON DELETE CASCADE,
  line_num INTEGER NOT NULL
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
    word_locations.word_id = words.rowid
  JOIN files
  ON
    files.rowid = word_locations.file_id
  JOIN filetypes
  ON
    filetypes.rowid = files.filetype_id
);


END;
