INSERT OR IGNORE INTO words (word,  lword,        kind,  pword,  pkind,  gpword,  gpkind)
VALUES                      (:word, LOWER(:word), :kind, :pword, :pkind, :gpword, :gpkind)
