UPDATE batches
SET
  duration = :duration,
  items    = :items
WHERE
  rowid = :batch_id

