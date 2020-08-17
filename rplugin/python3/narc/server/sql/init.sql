CREATE TABLE IF NOT EXISTS medits(
  old_prefix TEXT NOT NULL,
  new_prefix TEXT NOT NULL,
  old_suffix TEXT NOT NULL,
  new_suffix TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS snippets(
  kind    TEXT NOT NULL,
  match   TEXT NOT NULL,
  content TEXT NOT NULL
);


CREATE TABLE IF NOT EXISTS steps (
);
