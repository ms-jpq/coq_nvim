BEGIN;


CREATE TABLE IF NOT EXISTS words (
  key   BLOB NOT NULL,
  word  TEXT NOT NULL,
  lword TEXT NOT NULL,
  UNIQUE (key, word)
);
CREATE INDEX IF NOT EXISTS words_lword ON words (lword);


END;
