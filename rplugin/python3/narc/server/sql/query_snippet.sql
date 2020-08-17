SELECT
  snippets.kind AS kind,
  snippets.content AS content
FROM snippets
WHERE
  snippets.suggestions_id = ?