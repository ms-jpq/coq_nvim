BEGIN;


CREATE TABLE IF NOT EXISTS panes (
  rowid      INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL,
  window_id  INTEGER NOT NULL,
  pane_id    INTEGER NOT NULL,
  UNIQUE(session_id),
  UNIQUE(session_id, window_id),
  UNIQUE(session_id, window_id, pane_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS panes_session_id ON panes (session_id);
CREATE INDEX IF NOT EXISTS panes_window_id  ON panes (window_id);
CREATE INDEX IF NOT EXISTS panes_pane_id    ON panes (pane_id);


CREATE TABLE IF NOT EXISTS words (
  pane_id INTEGER NOT NULL REFERENCES panes (rowid) ON DELETE CASCADE,
  word  TEXT NOT NULL,
  lword TEXT NOT NULL AS (X_LOWER(word)) STORED,
  UNIQUE (pane_id, word)
);
CREATE INDEX IF NOT EXISTS words_pane_id ON words (pane_id);
CREATE INDEX IF NOT EXISTS words_word    ON words (word);
CREATE INDEX IF NOT EXISTS words_lword   ON words (lword);


END;
