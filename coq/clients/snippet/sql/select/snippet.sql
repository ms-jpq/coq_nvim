SELECT
  snippets.rowid AS snippet_id,
  snippets.grammar AS grammar,
  snippets.match AS match,
  snippets.content AS content,
  snippets.label AS label,
  snippets.doc AS doc
FROM snippets
JOIN matches
ON matches.snippet_id = snippets.rowid
WHERE
  :word <> ''
  AND
  snippets.filetype IN (
    SELECT
      dest
    FROM extensions_view
    WHERE
      src = :filetype
  )
  AND
  snippets.lmatch LIKE X_LIKE_ESC(X_LOWER(:word)) ESCAPE '!'

