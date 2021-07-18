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
  batch_id    BLOB    NOT NULL REFERENCES batches (rowid) ON UPDATE CASCADE ON DELETE CASCADE
  UNIQUE(batch_id, source_id)
) WITHOUT rowid;
CREATE INDEX IF NOT EXISTS instances_batch_id  ON instances (batch_id);
CREATE INDEX IF NOT EXISTS instances_source_id ON instances (source_id);


CREATE TABLE IF NOT EXISTS instance_stat (
  instance_id BLOB    NOT NULL REFERENCES instances (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  interrupted INTEGER NOT NULL,
  duration    REAL    NOT NULL,
  items       INTEGER NOT NULL,
);
CREATE INDEX IF NOT EXISTS instance_stat_instance_id ON instance_stat (instance_id);


CREATE TABLE IF NOT EXISTS inserted (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  instance_id BLOB    NOT NULL REFERENCES instances (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by     TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS inserted_instance_id ON inserted (instance_id);
CREATE INDEX IF NOT EXISTS inserted_sort_by     ON inserted (sort_by);



CREATE VIEW IF NOT EXISTS stat_interrupted_view AS
SELECT
  instances.source_id                                         AS source,
  COALESCE(SUM(COALESCE(instance_stat.interrupted, TRUE)), 0) AS interrupted
FROM instances
LEFT JOIN instance_stat
ON
  instance_stat.instance_id = instances.rowid
GROUP BY
  instances.source_id;


CREATE VIEW IF NOT EXISTS stat_avg_items_view AS
SELECT
  instances.source_id                                AS source,
  COALESCE(AVG(COALESCE(instance_stat.items, 0)), 0) AS avg_items
FROM instances
LEFT JOIN instance_stat
ON
  instance_stat.instance_id = instances.rowid
GROUP BY
  instances.source_id;


CREATE VIEW IF NOT EXISTS stat_duration_view AS
SELECT
  instances.source_id                      AS source,
  COALESCE(AVG(instance_stat.duration), 0) AS duration
FROM instances
LEFT JOIN instance_stat
ON
  instance_stat.instance_id = instances.rowid
GROUP BY
  instances.source_id
HAVING
  instance_stat.rowid <> NULL;


CREATE VIEW IF NOT EXISTS stat_duration_nointerrupt_view AS
SELECT
  instances.source_id                      AS source,
  COALESCE(AVG(instance_stat.duration), 0) AS duration
FROM instances
LEFT JOIN instance_stat
ON
  instance_stat.instance_id = instances.rowid
GROUP BY
  instances.source_id
HAVING
  NOT COALESCE(instance_stat.interrupted, TRUE);


CREATE VIEW IF NOT EXISTS stat_inserted_view AS
SELECT
  instances.source_id   AS source,
  COUNT(inserted.rowid) AS inserted
FROM instances
LEFT JOIN inserted
ON
  inserted.instance_id = instances.rowid
GROUP BY
  instances.source_id;


END;
