INSERT INTO snippets ( rowid          filetype,          grammar,          content,          label,          doc)
VALUES               (:rowid, X_NORM(:filetype), X_NORM(:grammar), X_NORM(:content), X_NORM(:label), X_NORM(:doc))
