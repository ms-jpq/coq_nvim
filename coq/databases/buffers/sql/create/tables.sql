BEGIN;


CREATE TABLE IF NOT EXISTS buffers (
  rowid     INTEGER NOT NULL PRIMARY KEY,
  filetype  TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS buffers_filetype ON buffers (filetype);


CREATE TABLE IF NOT EXISTS lines (
  rowid     BLOB    NOT NULL PRIMARY KEY,
  buffer_id INTEGER NOT NULL REFERENCES buffers (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  line_num  INTEGER NOT NULL,
  line      TEXT    NOT NULL
  -- TODO -- How to update line_num from back -> front in a single query
  -- UNIQUE(filename, line_num)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS liness_buffer_id ON lines (buffer_id);
CREATE INDEX IF NOT EXISTS lines_line_num   ON lines (line_num);


CREATE TABLE IF NOT EXISTS words (
  line_id BLOB NOT NULL REFERENCES lines (rowid) ON UPDATE CASCADE ON DELETE CASCADE,
  word    TEXT NOT NULL,
  lword   TEXT NOT NULL AS (LOWER(word)) STORED,
  sort_by TEXT NOT NULL AS (X_STRXFRM(lword)),
  UNIQUE(line_id, word)
);
CREATE INDEX IF NOT EXISTS words_line_id ON words (line_id);
CREATE INDEX IF NOT EXISTS words_word    ON words (word);
CREATE INDEX IF NOT EXISTS words_lword   ON words (lword);


END;
