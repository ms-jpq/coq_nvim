DROP TABLE IF EXISTS snippets;
DROP TABLE IF EXISTS ledits;
DROP TABLE IF EXISTS medits;
DROP TABLE IF EXISTS suggestions;
DROP TABLE IF EXISTS sources;
DROP TABLE IF EXISTS batches;


CREATE TABLE IF NOT EXISTS batches (
  p_row INTEGER NOT NULL,
  p_col INTEGER NOT NULL
);


CREATE TABLE IF NOT EXISTS sources (
  name          TEXT    NOT NULL,
  short_name    TEXT    NOT NULL,
  priority      INTEGER NOT NULL,
  ensure_unique BOOLEAN NOT NULL,
  use_cache     BOOLEAN NOT NULL
);


CREATE TABLE IF NOT EXISTS suggestions (
  batch_id         INTEGER NOT NULL,
  source_id        INTEGER NOT NULL,
  match            TEXT    NOT NULL,
  match_normalized TEXT    NOT NULL,
  label            TEXT,
  sortby           TEXT,
  kind             TEXT,
  doc              TEXT,
  FOREIGN KEY (batch_id)   REFERENCES batches  (rowid) ON DELETE CASCADE,
  FOREIGN KEY (source_id)  REFERENCES sources  (rowid) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS medits (
  suggestions_id INTEGER NOT NULL,
  old_prefix     TEXT    NOT NULL,
  new_prefix     TEXT    NOT NULL,
  old_suffix     TEXT    NOT NULL,
  new_suffix     TEXT    NOT NULL,
  FOREIGN KEY (suggestions_id) REFERENCES suggestions (rowid) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS ledits (
  suggestions_id INTEGER NOT NULL,
  begin_row      INTEGER NOT NULL,
  begin_col      INTEGER NOT NULL,
  end_row        INTEGER NOT NULL,
  end_col        INTEGER NOT NULL,
  text           INTEGER NOT NULL,
  FOREIGN KEY (suggestions_id) REFERENCES suggestions (rowid) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS snippets (
  suggestions_id INTEGER NOT NULL,
  kind           TEXT    NOT NULL,
  content        TEXT    NOT NULL,
  FOREIGN KEY (suggestions_id) REFERENCES suggestions (rowid) ON DELETE CASCADE
);
