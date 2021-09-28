INSERT OR IGNORE INTO words (buffer_id,  word, lword,        kind,  pword,  pkind,  gpword,  gpkind)
VALUES                      (:buffer_id :word, LOWER(:word), :kind, :pword, :pkind, :gpword, :gpkind)
