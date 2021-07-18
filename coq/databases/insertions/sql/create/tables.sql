BEGIN;


CREATE TABLE IF NOT EXISTS sources (
  name TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS batches (
  rowid BLOB NOT NULL PRIMARY KEY
) WITHOUT rowid;


CREATE TABLE IF NOT EXISTS instances (
  rowid       BLOB    NOT NULL PRIMARY KEY,
  source_id   TEXT    NOT NULL REFERENCES sources (name)  ON UPDATE CASCADE ON DELETE CASCADE,
  batch_id    BLOB    NOT NULL REFERENCES batches (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  interrupted INTEGER NOT NULL,
  duration    REAL    NOT NULL,
  items       INTEGER NOT NULL,
  UNIQUE(batch_id, source_id)
) WITHOUT rowid;
CREATE INDEX IF NOT EXISTS instances_batch_id  ON instances (batch_id);
CREATE INDEX IF NOT EXISTS instances_source_id ON instances (source_id);


CREATE TABLE IF NOT EXISTS inserted (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  instance_id BLOB    NOT NULL REFERENCES instances (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by     TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS inserted_instance_id ON inserted (instance_id);
CREATE INDEX IF NOT EXISTS inserted_sort_by     ON inserted (sort_by);



CREATE VIEW IF NOT EXISTS statistics_1 AS
SELECT
  sources.name AS source,
  CASE
    WHEN COUNT(*) = 0 THEN 0.0
    ELSE SUM(instances.interrupted) / COUNT(*)
  END AS interrupted
FROM sources
JOIN instances
ON
  instances.source_id = sources.name
GROUP BY
  sources.name


END;
