INSERT INTO files (        filename,          filetype,   mtime)
VALUES            (X_NORM(:filename), X_NORM(:filetype), :mtime)
ON CONFLICT (filename)
DO UPDATE SET filetype = X_NORM(:filetype)
              mtime    = :mtime

