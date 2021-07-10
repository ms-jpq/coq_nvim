INSERT INTO buffers ( rowid,  filetype)
VALUES              (:rowid, :filetype)
ON CONFLICT (rowid)
DO UPDATE SET filetype = :filetype
