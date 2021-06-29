BEGIN;


CREATE TABLE IF NOT EXISTS files (
  filename TEXT NOT NULL PRIMARY KEY,
  filetype TEXT NOT NULL,
  mtime    REAL NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_filetype ON files (filetype);



-- !! files 1:N tags
CREATE TABLE IF NOT EXISTS tags (
  `path`    TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  line      INTEGER,
  kind      TEXT    NOT NULL,
  name      TEXT    NOT NULL,
  lname     TEXT    NOT NULL AS (X_LOWER(name)) STORED,
  pattern   TEXT    NOT NULL,
  roles     TEXT,
  typeref   TEXT,
  scope     TEXT,
  scopeKind TEXT,
  `access`  TEXT
);
CREATE INDEX IF NOT EXISTS tags_path ON tags (`path`);
CREATE INDEX IF NOT EXISTS tags_line ON tags (line);
CREATE INDEX IF NOT EXISTS tags_name ON tags (name);
CREATE INDEX IF NOT EXISTS tags_lnam ON tags (lname);


END;
