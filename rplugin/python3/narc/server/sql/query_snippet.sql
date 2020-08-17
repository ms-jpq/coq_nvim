SELECT
  snippet_kinds.kind AS kind,
  snippets.content AS content
FROM snippets
JOIN snippet_kinds
ON
  snippet_kinds.rowid = snippets.kind_id;
WHERE
  snippets.suggestions_id = ?
