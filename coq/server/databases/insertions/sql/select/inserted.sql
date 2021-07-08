SELECT DISTINCT
  rowid   AS insert_order
  sort_by AS sort_by
FROM inserted
GROUP BY
  sort_by
ORDER BY
  rowid DESC
LIMIT :limit

