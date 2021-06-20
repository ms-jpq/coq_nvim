INSERT INTO files (        filename,          filetype)
VALUES            (X_NORM(:filename), X_NORM(:filetype))
ON CONFLICT (filename)
DO UPDATE SET filetype = :filetype
