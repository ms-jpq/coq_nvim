DELETE FROM buffers
WHERE
  EXISTS (
    SELECT
      TRUE
    FROM tmp.bufs
    WHERE
      tmp.bufs.buf_id = buffers.rowid
  )
