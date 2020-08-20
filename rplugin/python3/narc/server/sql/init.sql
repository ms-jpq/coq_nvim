BEGIN;

DROP TABLE IF EXISTS filetypes;
DROP TABLE IF EXISTS suggestions;


CREATE TABLE filetypes (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL UNIQUE
);
CREATE INDEX filetypes_filetype ON filetypes (filetype);


CREATE TABLE suggestions (
  match            TEXT    NOT NULL UNIQUE PRIMARY KEY,
  filetype_id      INTEGER NOT NULL REFERENCES filetypes (rowid) ON DELETE CASCADE,
  priority         INTEGER NOT NULL,
  match_normalized TEXT    NOT NULL,
  label            TEXT,
  sortby           TEXT,
  kind             TEXT,
  doc              TEXT
) WITHOUT ROWID;
CREATE INDEX suggestions_match_normalized ON suggestions (match_normalized);

END;
