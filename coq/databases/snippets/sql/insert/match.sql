INSERT OR IGNORE INTO matches (snippet_id,  match,  word_start,           lmatch)
VALUES                        (:snippet_id, :match, X_WORD_START(:match), LOWER(:match))
