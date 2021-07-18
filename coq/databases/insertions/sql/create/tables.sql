BEGIN;


CREATE TABLE IF NOT EXISTS sources (
  name TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS batches (
  rowid BLOB NOT NULL PRIMARY KEY
) WITHOUT rowid;


CREATE TABLE IF NOT EXISTS instances (
  rowid     BLOB NOT NULL PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources (name)  ON UPDATE CASCADE ON DELETE CASCADE,
  batch_id  BLOB NOT NULL REFERENCES batches (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  UNIQUE(batch_id, source_id)
) WITHOUT rowid;
CREATE INDEX IF NOT EXISTS instances_batch_id  ON instances (batch_id);
CREATE INDEX IF NOT EXISTS instances_source_id ON instances (source_id);


CREATE TABLE IF NOT EXISTS instance_stats (
  instance_id BLOB    NOT NULL REFERENCES instances (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  interrupted INTEGER NOT NULL,
  duration    REAL    NOT NULL,
  items       INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS instance_stats_instance_id ON instance_stats (instance_id);


CREATE TABLE IF NOT EXISTS inserted (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  instance_id BLOB    NOT NULL REFERENCES instances (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  sort_by     TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS inserted_instance_id ON inserted (instance_id);
CREATE INDEX IF NOT EXISTS inserted_sort_by     ON inserted (sort_by);


--
-- VIEWS 
--


CREATE VIEW IF NOT EXISTS instance_stats_view AS
SELECT
  instances.source_id                        AS source,
  COALESCE(instance_stats.interrupted, TRUE) AS interrupted,
  instance_stats.duration                    AS duration,
  COALESCE(instance_stats.items, 0)          AS items
FROM instances
LEFT JOIN instance_stats
ON
  instance_stats.instance_id = instances.rowid


CREATE VIEW IF NOT EXISTS stats_view AS
SELECT
  source_id                     AS source,
  COALESCE(SUM(interrupted), 0) AS interrupted,
  COALESCE(AVG(items), 0)       AS avg_items,
  COALESCE(X_MEDIAN(items), 0)  AS median_items
FROM instance_stats_view
GROUP BY
  source_id;


CREATE VIEW IF NOT EXISTS stats_nointerrupt_view AS
SELECT
  source_id                       AS source,
  COALESCE(AVG(duration), 0)      AS avg_duration,
  COALESCE(X_MEDIAN(duration), 0) AS median_duration
FROM instance_stats_view
GROUP BY
  source_id
HAVING
  NOT interrupted;


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
