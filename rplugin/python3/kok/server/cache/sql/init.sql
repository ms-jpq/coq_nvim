BEGIN;

DROP TABLE IF EXISTS filetypes;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS edit;


CREATE TABLE filetypes (
  rowid    INTEGER PRIMARY KEY,
  filetype TEXT NOT NULL UNIQUE,
) WITHOUT ROWID;


CREATE TABLE locations (
  rowid  INTEGER PRIMARY KEY,
  ro     INTEGER NOT NULL,
  co     INTEGER NOT NULL,
  UNIQUE (ro, co)
) WITHOUT ROWID;
CREATE INDEX locations_ro ON locations (ro);
CREATE INDEX locations_co ON locations (co);


CREATE TABLE edits (
  edit     TEXT PRIMARY KEY,
  filetype_id INTEGER NOT NULL REFERENCES filetype (rowid) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX edits_edit        ON edits (edit);
CREATE INDEX edits_filetype_id ON edits (filetype_id);


END;
