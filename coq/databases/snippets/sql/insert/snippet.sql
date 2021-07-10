INSERT OR IGNORE INTO snippets ( rowid,              filetype,               grammar,               content,               label,               doc)
VALUES                         (:rowid, X_NORMALIZE(:filetype), X_NORMALIZE(:grammar), X_NORMALIZE(:content), X_NORMALIZE(:label), X_NORMALIZE(:doc))

