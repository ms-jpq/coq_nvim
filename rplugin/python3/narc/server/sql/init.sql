BEGIN;

DROP TABLE IF EXISTS suggestions;

CREATE TABLE suggestions (
  match            TEXT    NOT NULL UNIQUE PRIMARY KEY,
  filetype         TEXT    NOT NULL,
  priority         INTEGER NOT NULL,
  match_normalized TEXT    NOT NULL,
  label            TEXT,
  sortby           TEXT,
  kind             TEXT,
  doc              TEXT
) WITHOUT ROWID;
CREATE INDEX suggestions_filetype         ON filetypes   (suggestions);
CREATE INDEX suggestions_match_normalized ON suggestions (match_normalized);

END;
