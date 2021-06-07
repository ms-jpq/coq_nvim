INSERT INTO files (filename,  filetype)
VALUES            (:filename, :filetype)
ON CONFLICT (filename)
DO UPDATE SET filetype = :filetype
