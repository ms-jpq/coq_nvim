SELECT
  snippets.rowid   AS snippet_id,
  snippets.grammar AS grammar,
  snippets.content AS content,
  snippets.label   AS label,
  snippets.doc     AS doc
FROM snippets
JOIN matches
ON matches.snippet_id = snippets.rowid
JOIN extensions_view
ON
  snippets.filetype = extensions_view.dest
WHERE
  :word <> ''
  AND
  extensions_view.src = :filetype
  AND
  matches.lmatch LIKE X_LIKE_ESC(X_LOWER(X_NORM(:word))) ESCAPE '!'

