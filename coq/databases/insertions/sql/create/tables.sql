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
CREATE INDEX IF NOT EXISTS instances_source_id ON instances (source_id);
CREATE INDEX IF NOT EXISTS instances_batch_id  ON instances (batch_id);


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
  instances.source_id                     AS source,
  COALESCE(instance_stats.interrupted, 1) AS interrupted,
  instance_stats.duration                 AS duration,
  COALESCE(instance_stats.items, 0)       AS items
FROM instances
LEFT JOIN instance_stats
ON
  instance_stats.instance_id = instances.rowid;


CREATE VIEW IF NOT EXISTS quantiles_view AS
SELECT
  source                                                  AS source,
  items,
  duration,
  NTILE(100) OVER (PARTITION BY source ORDER BY items)    AS q_items,
  NTILE(100) OVER (PARTITION BY source ORDER BY duration) AS q_duration
FROM instance_stats_view;


CREATE VIEW IF NOT EXISTS duration_quantiles_view AS
SELECT
  source,
  q_duration,
  MAX(duration) AS duration
FROM quantiles_view
GROUP BY
  source,
  q_duration;


CREATE VIEW IF NOT EXISTS items_quantiles_view AS
SELECT
  source,
  q_items,
  MAX(items) AS items
FROM quantiles_view
GROUP BY
  source,
  q_items;


CREATE VIEW IF NOT EXISTS stats_summaries_view AS
SELECT
  source                         AS source,
  COALESCE(SUM(interrupted), 0)  AS interrupted,
  COALESCE(AVG(duration), 0)     AS avg_duration,
  COALESCE(AVG(items), 0)        AS avg_items
FROM instance_stats_view
GROUP BY
  source;


CREATE VIEW IF NOT EXISTS stats_inserted_view AS
SELECT
  instances.source_id   AS source,
  COUNT(inserted.rowid) AS inserted
FROM instances
LEFT JOIN inserted
ON
  inserted.instance_id = instances.rowid
GROUP BY
  instances.source_id;


CREATE VIEW IF NOT EXISTS stats_view AS
SELECT
  sources.name                                   AS source,
  COALESCE(stats_summaries_view.interrupted, 0)  AS interrupted,
  COALESCE(stats_summaries_view.avg_items, 0)    AS avg_items,
  COALESCE(stats_summaries_view.avg_duration, 0) AS avg_duration,
  COALESCE(stats_inserted_view.inserted, 0)      AS inserted,
  COALESCE(
    (
      SELECT
        duration
      FROM
        duration_quantiles_view
      WHERE
        duration_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_duration - 10)
      LIMIT
        1
    ),
    0
  ) AS q10_duration,
  COALESCE(
    (
      SELECT
        duration
      FROM
        duration_quantiles_view
      WHERE
        duration_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_duration - 50)
      LIMIT
        1
    ),
    0
  ) AS q50_duration,
  COALESCE(
    (
      SELECT
        duration
      FROM
        duration_quantiles_view
      WHERE
        duration_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_duration - 95)
      LIMIT
        1
    ),
    0
  ) AS q95_duration,
  COALESCE(
    (
      SELECT
        duration
      FROM
        duration_quantiles_view
      WHERE
        duration_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_duration - 99)
      LIMIT
        1
    ),
    0
  ) AS q99_duration,
  COALESCE(
    (
      SELECT
        items
      FROM
        items_quantiles_view
      WHERE
        items_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_items - 50)
      LIMIT
        1
    ),
    0
  ) AS q50_items,
  COALESCE(
    (
      SELECT
        items
      FROM
        items_quantiles_view
      WHERE
        items_quantiles_view.source = sources.name
      ORDER BY
        ABS(q_items - 99)
      LIMIT
        1
    ),
    0
  ) AS q99_items
FROM sources
LEFT JOIN stats_summaries_view
ON stats_summaries_view.source = sources.name
LEFT JOIN stats_inserted_view
ON stats_inserted_view.source = sources.name;


END;
