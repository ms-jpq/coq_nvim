INSERT INTO files ( buffer_id,               filetype)
VALUES            (:buffer_id, X_NORMALIZE(:filetype))
ON CONFLICT (buffer_id)
DO UPDATE SET filetype = X_NORMALIZE(:filetype)
