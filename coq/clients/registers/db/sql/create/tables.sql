BEGIN;


CREATE TABLE IF NOT EXISTS registers (
  register TEXT NOT NULL PRIMARY KEY
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS words (
  register TEXT       NOT NULL REFERENCES registers (register) ON UPDATE CASCADE ON DELETE CASCADE,
  word     TEXT       NOT NULL,
  lword    TEXT       NOT NULL,
  UNIQUE   (register, word)
);
CREATE INDEX IF NOT EXISTS words_register ON words (register);
CREATE INDEX IF NOT EXISTS words_word     ON words (word);
CREATE INDEX IF NOT EXISTS words_lword    ON words (lword);


CREATE TABLE IF NOT EXISTS lines (
  register TEXT       NOT NULL REFERENCES registers (register) ON UPDATE CASCADE ON DELETE CASCADE,
  word     TEXT       NOT NULL,
  lword    TEXT       NOT NULL,
  line     TEXT       NOT NULL,
  UNIQUE   (register, line)
);
CREATE INDEX IF NOT EXISTS lines_register ON lines (register);
CREATE INDEX IF NOT EXISTS lines_word     ON lines (word);
CREATE INDEX IF NOT EXISTS lines_lword    ON lines (lword);


END;
