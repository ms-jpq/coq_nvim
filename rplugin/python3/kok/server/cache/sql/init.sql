BEGIN;

DROP TABLE IF EXISTS filenames;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS edits;


CREATE TABLE filenames (
  rowid    INTEGER PRIMARY KEY,
  filename TEXT NOT NULL UNIQUE,
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
  filename_id INTEGER NOT NULL REFERENCES filename (rowid) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX edits_edit        ON edits (edit);
CREATE INDEX edits_filename_id ON edits (filename_id);


END;
