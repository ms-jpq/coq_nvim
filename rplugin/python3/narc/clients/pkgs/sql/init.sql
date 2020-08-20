CREATE TABLE words (
  word  TEXT NOT NULL UNIQUE,
  nword TEXT NOT NULL
);

CREATE INDEX words_nword ON words (nword);
