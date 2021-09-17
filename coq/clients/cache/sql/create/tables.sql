BEGIN;


CREATE TABLE IF NOT EXISTS words (
  word       TEXT    NOT NULL PRIMARY KEY,
  word_start INTEGER NOT NULL,
  lword      TEXT    NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS words_lword ON words (lword);


END;
