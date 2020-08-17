SELECT
  kind,
  content,
FROM snippets_view
WHERE
  snippets_view.suggestions_id = ?
