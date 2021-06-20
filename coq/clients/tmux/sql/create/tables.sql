BEGIN;


CREATE TABLE IF NOT EXISTS words (
  pane_id TEXT NOT NULL,
  word    TEXT NOT NULL,
  lword   TEXT NOT NULL AS (X_LOWER(X_NORM(word))) STORED,
  UNIQUE (pane_id, word)
);
CREATE INDEX IF NOT EXISTS words_pane_id ON words (pane_id);
CREATE INDEX IF NOT EXISTS words_word    ON words (word);
CREATE INDEX IF NOT EXISTS words_lword   ON words (lword);


END;
