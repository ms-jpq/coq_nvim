BEGIN;

DROP TABLE IF EXISTS filetypes;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS counts;


CREATE TABLE filetypes (
  rowid    INTEGER PRIMARY KEY,
  filetype TEXT NOT NULL UNIQUE,
) WITHOUT ROWID;


CREATE TABLE locations (
  word      TEXT    NOT NULL,
  row_index INTEGER NOT NULL
);
CREATE INDEX locations_word ON locations (word);


CREATE TABLE counts (
  word        TEXT PRIMARY KEY,
  filetype_id INTEGER NOT NULL REFERENCES filetype (rowid) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX counts_word        ON counts (word);
CREATE INDEX counts_filetype_id ON counts (filetype_id);


END;
