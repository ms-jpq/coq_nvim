BEGIN;

DROP TABLE IF EXISTS filetypes;
DROP TABLE IF EXISTS snippets;
DROP TABLE IF EXISTS ledits;
DROP TABLE IF EXISTS medits;
DROP TABLE IF EXISTS suggestions;
DROP TABLE IF EXISTS sources;
DROP TABLE IF EXISTS batches;


CREATE TABLE filetypes (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL UNIQUE
);
CREATE INDEX filetypes_filetype ON filetypes (filetype);


CREATE TABLE batches (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype_id INTEGER NOT NULL REFERENCES filetypes (rowid) ON DELETE CASCADE,
  p_row       INTEGER NOT NULL,
  p_col       INTEGER NOT NULL
);


CREATE TABLE sources (
  rowid         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL UNIQUE,
  short_name    TEXT    NOT NULL UNIQUE,
  priority      INTEGER NOT NULL,
  ensure_unique BOOLEAN NOT NULL,
  use_cache     BOOLEAN NOT NULL
);
CREATE INDEX sources_use_cache ON sources (use_cache);


CREATE TABLE suggestions (
  rowid            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  batch_id         INTEGER NOT NULL REFERENCES batches (rowid) ON DELETE CASCADE,
  source_id        INTEGER NOT NULL REFERENCES sources (rowid) ON DELETE CASCADE,
  match            TEXT    NOT NULL,
  match_normalized TEXT    NOT NULL,
  label            TEXT,
  sortby           TEXT,
  kind             TEXT,
  doc              TEXT
);
CREATE INDEX suggestions_match_normalized ON suggestions (match_normalized);


CREATE TABLE medits (
  suggestions_id INTEGER NOT NULL REFERENCES suggestions (rowid) ON DELETE CASCADE,
  old_prefix     TEXT    NOT NULL,
  new_prefix     TEXT    NOT NULL,
  old_suffix     TEXT    NOT NULL,
  new_suffix     TEXT    NOT NULL
);


CREATE TABLE ledits (
  suggestions_id INTEGER NOT NULL REFERENCES suggestions (rowid) ON DELETE CASCADE,
  begin_row      INTEGER NOT NULL,
  begin_col      INTEGER NOT NULL,
  end_row        INTEGER NOT NULL,
  end_col        INTEGER NOT NULL,
  text           INTEGER NOT NULL
);


CREATE TABLE snippets (
  suggestions_id INTEGER NOT NULL REFERENCES suggestions (rowid) ON DELETE CASCADE,
  kind           TEXT    NOT NULL,
  content        TEXT    NOT NULL
);

END;
