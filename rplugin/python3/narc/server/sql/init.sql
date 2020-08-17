CREATE TABLE IF NOT EXISTS batches (
  p_row INTEGER NOT NULL,
  p_col INTEGER NOT NULL,
);


CREATE TABLE IF NOT EXISTS medits (
  old_prefix TEXT NOT NULL,
  new_prefix TEXT NOT NULL,
  old_suffix TEXT NOT NULL,
  new_suffix TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS ledits (
  begin_row INTEGER NOT NULL,
  begin_col INTEGER NOT NULL,
  end_row   INTEGER NOT NULL,
  end_col   INTEGER NOT NULL,
  text      INTEGER NOT NULL
);


CREATE TABLE IF NOT EXISTS snippets (
  kind    TEXT NOT NULL,
  content TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS suggestions (
  batch_id         INTEGER NOT NULL,
  medit_id         INTEGER,
  snippet_id       INTEGER,
  match            TEXT    NOT NULL,
  match_normalized TEXT    NOT NULL,
  label            TEXT,
  sortby           TEXT,
  kind             TEXT,
  doc              TEXT    NOT NULL,
  ensure_unique    INTEGER NOT NULL,
  match_syms       INTEGER NOT NULL
  FOREIGN KEY (batch_id)   REFERENCES batches  (rowid),
  FOREIGN KEY (medit_id)   REFERENCES medits   (rowid)
  FOREIGN KEY (snippet_id) REFERENCES snippets (rowid)
);


CREATE TABLE IF NOT EXISTS suggestion_ledits (
  suggestions_id INTEGER NOT NULL,
  ledit_id       INTEGER NOT NULL,
  FOREIGN KEY (suggestions_id) REFERENCES suggestions (rowid),
  FOREIGN KEY (ledit_id)       REFERENCES ledits      (rowid)
);
