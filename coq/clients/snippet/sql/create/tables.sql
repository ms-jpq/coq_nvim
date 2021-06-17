BEGIN;


CREATE TABLE IF NOT EXISTS filetypes (
  filetype TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS extensions (
  src  TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  dest TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  UNIQUE (src, dest)
);
CREATE INDEX extensions_src ON extensions (src);


CREATE TABLE IF NOT EXISTS snippets (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  grammar  TEXT    NOT NULL,
  content  TEXT    NOT NULL,
  label    TEXT,
  doc      TEXT
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS matches (
  snippet_id INTEGER NOT NULL REFERENCES snippets (rowid) ON DELETE CASCADE,
  match      TEXT    NOT NULL,
  lmatch     TEXT    NOT NULL AS (X_LOWER(match)) STORED,
  UNIQUE(snippet_id, match)
) WITHOUT ROWID;
CREATE INDEX matches_lmatch ON matches (lmatch);


CREATE TABLE IF NOT EXISTS options (
  snippet_id INTEGER NOT NULL REFERENCES snippets (rowid) ON DELETE CASCADE,
  option     TEXT    NOT NULL,
  UNIQUE(snippet_id, option)
);


CREATE VIEW IF NOT EXISTS extensions_view AS
WITH RECURSIVE all_exts AS (
  SELECT
    1 AS lvl,
    e1.src,
    e1.dest
  FROM extensions AS e1
  UNION ALL
  SELECT
    all_exts.lvl + 1 AS lvl,
    all_exts.src,
    e2.dest
  FROM extensions AS e2
  JOIN all_exts
  ON
    all_exts.dest = e2.src
)
SELECT
  rowid AS src,
  rowid AS dest
FROM filetypes
UNION ALL
SELECT
  src,
  dest
FROM all_exts
WHERE
  lvl < 10;


END;

