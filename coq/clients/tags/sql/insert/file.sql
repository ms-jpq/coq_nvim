INSERT INTO files (             filename,               filetype,   mtime)
VALUES            (X_NORMALIZE(:filename), X_NORMALIZE(:filetype), :mtime)
ON CONFLICT (filename)
DO UPDATE SET filetype = X_NORMALIZE(:filetype)

