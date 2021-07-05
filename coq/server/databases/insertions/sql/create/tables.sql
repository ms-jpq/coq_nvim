BEGIN;


CREATE TABLE IF NOT EXISTS sources (
  name TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS batch (
  rowid INTEGER NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS durations (
  batch_id INTEGER NOT NULL,
  duration REAL    NOT NULL,
  items    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS durations_batch_id ON durations (batch_id);


CREATE TABLE IF NOT EXISTS inserted (
  rowid     INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  source_id TEXT    NOT NULL REFERENCES sources (name)  ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by   TEXT    NOT NULL
  UNIQUE(source_id, batch_id)
);
CREATE INDEX IF NOT EXISTS inserted_source_id ON inserted (source_id);


CREATE TABLE IF NOT EXISTS candidates (
  rowid     INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  batch_id  INTEGER NOT NULL REFERENCES batch (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by   TEXT    NOT NULL UNIQUE,
  UNIQUE(source_id, batch_id)
);
CREATE INDEX IF NOT EXISTS candidates_batch_id ON candidates (batch_id);


END;
