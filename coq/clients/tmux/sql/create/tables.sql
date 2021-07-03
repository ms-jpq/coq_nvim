BEGIN;


CREATE TABLE IF NOT EXISTS panes (
  pane_id TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS words (
  pane_id TEXT NOT NULL REFERENCES panes (pane_id) ON DELETE CASCADE,
  word    TEXT NOT NULL,
  lword   TEXT NOT NULL AS (X_LOWER(word)) STORED,
  sort_by TEXT NOT NULL AS (X_STRXFRM(lword)),
  UNIQUE (pane_id, word)
);
CREATE INDEX IF NOT EXISTS words_pane_id ON words (pane_id);
CREATE INDEX IF NOT EXISTS words_word    ON words (word);
CREATE INDEX IF NOT EXISTS words_lword   ON words (lword);


END;
