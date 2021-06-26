INSERT INTO files (             filename,               filetype)
VALUES            (X_NORMALIZE(:filename), X_NORMALIZE(:filetype))
ON CONFLICT (filename)
DO UPDATE SET filetype = X_NORMALIZE(:filetype)
