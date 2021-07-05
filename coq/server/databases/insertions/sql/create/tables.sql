BEGIN;


CREATE TABLE IF NOT EXISTS sources (
  name TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS batches (
  rowid     BLOB    NOT NULL PRIMARY KEY,
  source_id TEXT    NOT NULL REFERENCES sources (name) ON UPDATE CASCADE ON DELETE CASCADE,
  duration  REAL    NOT NULL,
  items     INTEGER NOT NULL
) WITHOUT rowid;
CREATE INDEX IF NOT EXISTS batches_source_id ON batches (source_id);


CREATE TABLE IF NOT EXISTS inserted (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  batch_id BLOB    NOT NULL REFERENCES batches (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by  TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS inserted_batch_id ON inserted (batch_id);
CREATE INDEX IF NOT EXISTS inserted_sort_by  ON inserted (sort_by);


CREATE TABLE IF NOT EXISTS candidates (
  rowid   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  sort_by TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS candidates_sort_by ON candidates (sort_by);


END;
