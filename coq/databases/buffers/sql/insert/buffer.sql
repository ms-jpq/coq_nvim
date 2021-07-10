INSERT INTO buffers ( rowid,              filetype)
VALUES              (:rowid, X_NORMALIZE(:filetype))
ON CONFLICT (rowid)
DO UPDATE SET filetype = X_NORMALIZE(:filetype)
