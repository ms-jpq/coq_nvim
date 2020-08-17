CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5(
  word,
  nword
)
