INSERT OR IGNORE INTO words (buffer_id,  filename,               word,  lword,        kind,  pword,  pkind,  gpword,  gpkind)
VALUES                      (:buffer_id, X_NORM_CASE(:filename), :word, LOWER(:word), :kind, :pword, :pkind, :gpword, :gpkind)
