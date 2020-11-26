BEGIN;


DROP TABLE IF EXISTS filenames;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS edits;


CREATE TABLE filenames (
  rowid    INTEGER PRIMARY KEY,
  filename TEXT NOT NULL UNIQUE
) WITHOUT ROWID;


CREATE TABLE locations (
  rowid       INTEGER PRIMARY KEY,
  ro          INTEGER NOT NULL,
  co          INTEGER NOT NULL,
  filename_id INTEGER NOT NULL REFERENCES filenames (rowid) ON DELETE CASCADE,
  UNIQUE (ro, co, filename_id)
) WITHOUT ROWID;
CREATE INDEX locations_ro ON locations (ro);
CREATE INDEX locations_co ON locations (co);
CREATE INDEX locations_filename_id ON locations (filename_id);


CREATE TABLE edits (
  edit        TEXT PRIMARY KEY,
  location_id INTEGER NOT NULL REFERENCES locations (rowid) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX edits_edit ON edits (edit);


CREATE VIEW main_view AS
SELECT
  filenames.filename AS filename,
  locations.ro AS ro,
  locations.co AS co,
  edits.edit AS edit
FROM filenames
JOIN locations
ON
  locations.filename_id = filenames.rowid
JOIN edits
ON
  edits.location_id = locations.rowid;


END;
