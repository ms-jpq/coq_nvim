BEGIN;


CREATE TABLE IF NOT EXISTS filetypes (
  rowid    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype TEXT    NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS extensions (
  rowid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  src   INTEGER NOT NULL REFERENCES filetypes (rowid) ON DELETE CASCADE,
  dest  INTEGER NOT NULL REFERENCES filetypes (rowid) ON DELETE CASCADE,
  UNIQUE (src, dest)
);
CREATE INDEX extensions_src ON extensions (src);


CREATE TABLE IF NOT EXISTS options (
  rowid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name  TEXT    NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS snippet_kinds (
  rowid   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name    TEXT    NOT NULL UNIQUE,
  display TEXT    NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS snippets (
  rowid       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  filetype_id INTEGER NOT NULL REFERENCES filetypes     (rowid) ON DELETE CASCADE,
  kind_id     INTEGER NOT NULL REFERENCES snippet_kinds (rowid) ON DELETE CASCADE,
  content     TEXT    NOT NULL,
  label       TEXT,
  doc         TEXT
);


CREATE TABLE IF NOT EXISTS snippet_matches (
  rowid      INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  snippet_id INTEGER NOT NULL REFERENCES snippets (rowid) ON DELETE CASCADE,
  match      TEXT    NOT NULL,
  UNIQUE (snippet_id, match)
);
CREATE INDEX snippet_matches_match ON snippet_matches (match);


CREATE TABLE IF NOT EXISTS snippet_options (
  rowid      INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  snippet_id INTEGER NOT NULL REFERENCES snippets (rowid) ON DELETE CASCADE,
  option_id  INTEGER NOT NULL REFERENCES options  (rowid) ON DELETE CASCADE
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


CREATE VIEW IF NOT EXISTS snippets_matches_view AS
SELECT
  snippet_id AS snippet_id,
  count(match) AS aliases,
  group_concat(match, ' | ') AS matches
FROM snippet_matches
GROUP BY
  snippet_id;


CREATE VIEW IF NOT EXISTS snippets_options_view AS
SELECT
  snippet_options.snippet_id AS snippet_id,
  group_concat(options.name, ',') AS options
FROM snippet_options
JOIN options
ON
  options.rowid = snippet_options.option_id
GROUP BY
  snippet_options.snippet_id;


CREATE VIEW IF NOT EXISTS snippets_view AS
SELECT
  snippets.rowid AS snippet_id,
  ft_dest.filetype AS filetype,
  ft_src.filetype AS source_filetype,
  snippet_kinds.name AS kind,
  snippet_kinds.display AS kind_name,
  snippets.content AS content,
  snippets.label AS label,
  snippets.doc AS doc
FROM extensions_view
JOIN filetypes AS ft_dest
ON
  ft_dest.rowid = extensions_view.dest
JOIN filetypes AS ft_src
ON
  ft_src.rowid = extensions_view.src
JOIN snippets
ON
  snippets.filetype_id = extensions_view.src
JOIN snippet_kinds
ON
  snippet_kinds.rowid = snippets.kind_id;


CREATE VIEW IF NOT EXISTS overview AS
SELECT
  snippets_view.filetype AS filetype,
  snippets_view.source_filetype AS source_filetype,
  snippets_view.kind AS kind,
  snippets_matches_view.matches AS matches,
  snippets_options_view.options AS options,
  snippets_view.content AS content,
  snippets_view.label AS label,
  snippets_view.doc AS doc
FROM snippets_view
LEFT JOIN snippets_options_view
ON
  snippets_options_view.snippet_id = snippets_view.snippet_id
LEFT JOIN snippets_matches_view
ON
  snippets_matches_view.snippet_id = snippets_view.snippet_id;


CREATE VIEW IF NOT EXISTS query_view AS
SELECT
  snippets_view.filetype AS filetype,
  snippets_view.source_filetype AS source_filetype,
  snippet_matches.match AS match,
  snippets_view.kind AS kind,
  snippets_view.kind_name AS kind_name,
  snippets_view.content AS content,
  snippets_view.label AS label,
  snippets_view.doc AS doc
FROM snippet_matches
JOIN snippets_view
ON
  snippets_view.snippet_id = snippet_matches.snippet_id;


CREATE VIEW IF NOT EXISTS dump_view AS
SELECT
  snippet_kinds.name AS kind,
  filetypes.filetype AS filetype,
  snippets.content AS content,
  snippets.label AS label,
  snippets.doc AS doc
FROM snippets
JOIN snippet_kinds
ON
  snippet_kinds.rowid = snippets.kind_id
JOIN filetypes
ON
  filetypes.rowid = snippets.filetype_id;


END;

