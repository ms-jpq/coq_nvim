BEGIN;


CREATE TABLE IF NOT EXISTS filetypes (
  filetype TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS extensions (
  src  TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  dest TEXT NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  UNIQUE (src, dest)
);
CREATE INDEX IF NOT EXISTS extensions_src ON extensions (src);


CREATE TABLE IF NOT EXISTS snippets (
  rowid    INTEGER NOT NULL PRIMARY KEY,
  filetype TEXT    NOT NULL REFERENCES filetypes (filetype) ON DELETE CASCADE,
  grammar  TEXT    NOT NULL,
  content  TEXT    NOT NULL,
  label    TEXT    NOT NULL,
  doc      TEXT    NOT NULL
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS matches (
  snippet_id INTEGER NOT NULL REFERENCES snippets (rowid) ON DELETE CASCADE,
  match      TEXT    NOT NULL,
  lmatch     TEXT    NOT NULL AS (X_LOWER(match)) STORED,
  UNIQUE(snippet_id, match)
);
CREATE INDEX IF NOT EXISTS matches_snippet_id ON matches (snippet_id);
CREATE INDEX IF NOT EXISTS matches_lmatch     ON matches (lmatch);


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
  filetypes.filetype AS src,
  filetypes.filetype AS dest
FROM filetypes
UNION ALL
SELECT
  all_exts.src,
  all_exts.dest
FROM all_exts
WHERE
  lvl < 10;


END;

