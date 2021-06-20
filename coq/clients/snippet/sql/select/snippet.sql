SELECT
  snippets.rowid AS snippet_id,
  snippets.grammar AS grammar,
  snippets.content AS content,
  snippets.label AS label,
  snippets.doc AS doc
FROM snippets
JOIN matches
ON matches.snippet_id = snippets.rowid
JOIN (
  SELECT DISTINCT
    dest AS filetype
  FROM extensions_view
  WHERE
    src = :filetype
  ) AS filetypes
ON
  snippets.filetype = filetypes.filetype
WHERE
  :word <> ''
  AND
  snippets.filetype IN
  AND
  matches.lmatch LIKE X_LIKE_ESC(X_LOWER(:word)) ESCAPE '!'

