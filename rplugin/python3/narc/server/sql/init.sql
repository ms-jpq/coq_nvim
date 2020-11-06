BEGIN;

DROP TABLE IF EXISTS word_location;
DROP TABLE IF EXISTS word_count;


CREATE TABLE word_location (
  word      TEXT    NOT NULL,
  row_index INTEGER NOT NULL
);
CREATE INDEX word_location_word ON word_location (word);


CREATE TABLE word_count (
  word     TEXT PRIMARY KEY,
  filetype TEXT NOT NULL,
) WITHOUT ROWID;
CREATE INDEX word_count_word     ON word_count (word);
CREATE INDEX word_count_filetype ON word_count (filetype);


END;
