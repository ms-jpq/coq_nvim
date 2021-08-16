INSERT OR IGNORE INTO matches ( snippet_id,  match, lmatch)
VALUES                        (:snippet_id, :match, LOWER(:match))
