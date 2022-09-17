BEGIN;

CREATE TABLE IF NOT EXISTS
  panes (
    pane_id TEXT NOT NULL PRIMARY KEY,
    session_name TEXT NOT NULL,
    window_index INTEGER NOT NULL,
    window_name TEXT NOT NULL,
    pane_index INTEGER NOT NULL,
    pane_title TEXT NOT NULL
  ) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS
  words (
    pane_id TEXT NOT NULL REFERENCES panes (pane_id) ON UPDATE CASCADE ON DELETE CASCADE,
    word TEXT NOT NULL,
    lword TEXT NOT NULL,
    UNIQUE (pane_id, word)
  );

CREATE INDEX IF NOT EXISTS words_pane_id ON words (pane_id);

CREATE INDEX IF NOT EXISTS words_word ON words (word);

CREATE INDEX IF NOT EXISTS words_lword ON words (lword);

CREATE VIEW IF NOT EXISTS
  words_view AS
SELECT
  words.word,
  words.lword,
  panes.pane_id,
  panes.session_name,
  panes.window_index,
  panes.window_name,
  panes.pane_index,
  panes.pane_title
FROM
  panes
  JOIN words ON words.pane_id = panes.pane_id
GROUP BY
  words.word
HAVING
  words.word <> '';

END;
