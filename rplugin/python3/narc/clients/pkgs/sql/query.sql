SELECT word, nword
FROM words
WHERE
    nword MATCH ?
    AND
    nword <> ?
