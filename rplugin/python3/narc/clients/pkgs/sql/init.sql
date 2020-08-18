CREATE TABLE words (
  word  TEXT NOT NULL,
  nword TEXT NOT NULL
);

CREATE INDEX words_nword ON words (nword);
