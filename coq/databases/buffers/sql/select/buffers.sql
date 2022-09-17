SELECT
  buffers.rowid,
  COUNT(lines.rowid) AS line_count
FROM
  buffers
  JOIN lines ON lines.buffer_id = buffers.rowid
GROUP BY
  buffers.rowid
