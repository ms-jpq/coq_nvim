BEGIN;


CREATE TABLE IF NOT EXISTS files (
  filename TEXT NOT NULL PRIMARY KEY,
  filetype TEXT NOT NULL,
  mtime    REAL NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_filetype ON files (filetype);


-- !! files 1:N tags
CREATE TABLE IF NOT EXISTS tags (
  filename TEXT    NOT NULL REFERENCES files (filename) ON DELETE CASCADE,
  line_num INTEGER NOT NULL,
  line     TEXT    NOT NULL,
  kind     TEXT    NOT NULL,
  name     TEXT    NOT NULL,
  lname    TEXT    NOT NULL AS (X_LOWER(name)) STORED,
);
CREATE INDEX IF NOT EXISTS tags_filename ON tags (filename);
CREATE INDEX IF NOT EXISTS tags_lname    ON tags (lname);
CREATE INDEX IF NOT EXISTS tags_line_num ON tags (line_num);
CREATE INDEX IF NOT EXISTS tags_name     ON tags (name);
CREATE INDEX IF NOT EXISTS tags_lname    ON tags (lname);


END;
