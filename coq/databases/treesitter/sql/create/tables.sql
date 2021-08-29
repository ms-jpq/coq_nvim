BEGIN;


CREATE TABLE IF NOT EXISTS words (
  word   TEXT NOT NULL PRIMARY KEY,
  lword  TEXT NOT NULL,
  kind   TEXT NOT NULL,
  pword  TEXT,
  pkind  TEXT,
  gpword TEXT,
  gpkind TEXT
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS words_lword ON words (lword);


END;
